#!/usr/bin/env python3
"""Measure Canary's sentiment track from open data → site/data/sentiment.json.

Measured, not rated: no AI judgement is involved, nothing here changes a signal's status, and the
World State index ignores it. Two parts, configured in signals/sentiment.yaml:

  media       News tone and share of coverage for each issue, from the GDELT Global Knowledge
              Graph 2.1 (English plus machine-translated coverage in ~65 languages). One 15-minute
              file per stream at 00, 06, 12 and 18 UTC is aggregated into daily sums. The headline is
              the pooled tone of the last 7 days, ranked against every 7-day window in the 180 days
              before it, so each issue is compared only with itself.
  confidence  OECD composite consumer confidence (long-run average = 100): latest value and derived
              statistics only, because some national survey inputs belong to third parties.

GDELT's terms allow redistribution with a citation, so daily sums are stored and published.

Usage:
  python scripts/fetch_sentiment.py                 # normal run: fetch slots not yet stored
  python scripts/fetch_sentiment.py --backfill 180  # one-off: fill daily history (~1,400 files)
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
import statistics
import sys
import time
import urllib.error
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site" / "data" / "sentiment.json"
CFG = ROOT / "signals" / "sentiment.yaml"
# Deliberately generic: no personal or contact details are sent to third parties.
UA = "Mozilla/5.0 (compatible; CanaryBot/1.2; open-data status board)"
GDELT = "https://data.gdeltproject.org/gdeltv2/{stamp}.{stream}gkg.csv.zip"
OECD = "https://sdmx.oecd.org/public/rest/data/{flow}/{key}?startPeriod={since}&format=csvfile"
NOW = datetime.now(timezone.utc)
SLOT_BUFFER_DAYS = 3      # raw per-slot sums kept so a late or failed slot can be filled in
DAYS_CAP = 400            # daily history kept (baseline 180 days + 7-day windows + sparkline)
SPARK_DAYS = 90
LIVE_MAX_SLOTS = 16       # bound the work a single scheduled run can do
BANDS = (  # (minimum share of comparable windows that were less negative, key, label)
    (90, "much-gloomier", "Much gloomier than usual"),
    (75, "gloomier", "Gloomier than usual"),
    (26, "typical", "Typical"),
    (11, "brighter", "Brighter than usual"),
    (0, "much-brighter", "Much brighter than usual"),
)


class NotFound(Exception):
    pass


def get(url: str, timeout: int = 90) -> bytes:
    last = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise NotFound(url) from e
            last = e
        except Exception as e:  # noqa: BLE001
            last = e
        time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"{url}: {last}")


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def config() -> dict:
    return yaml.safe_load(CFG.read_text())


# ───────────────────────── GDELT media tone ─────────────────────────

def matchers(cfg: dict) -> list[tuple[str, frozenset, tuple]]:
    out = []
    for iss in cfg["media"]["issues"]:
        exact = frozenset(t for t in iss["themes"] if not t.endswith("*"))
        prefixes = tuple(t[:-1] for t in iss["themes"] if t.endswith("*"))
        out.append((iss["id"], exact, prefixes))
    return out


def parse_gkg(text: str, match: list, min_words: int) -> dict:
    """Pool one GKG file into {n, t, i: [[n, tone_sum] per issue]} (V1 themes, V1.5 tone)."""
    n, t = 0, 0.0
    per = [[0, 0.0] for _ in match]
    for line in text.split("\n"):
        c = line.split("\t", 16)
        if len(c) < 16:
            continue
        tone = c[15].split(",")
        if len(tone) < 7:
            continue
        try:
            tv, words = float(tone[0]), int(float(tone[6]))
        except ValueError:
            continue
        if words < min_words:
            continue
        n += 1
        t += tv
        if not c[7]:
            continue
        themes = c[7].split(";")
        tset = set(themes)
        for k, (_, exact, prefixes) in enumerate(match):
            if not tset.isdisjoint(exact) or (prefixes and any(x.startswith(prefixes) for x in themes)):
                per[k][0] += 1
                per[k][1] += tv
    return {"n": n, "t": t, "i": per}


def add(a: dict | None, b: dict) -> dict:
    if a is None:
        return {"n": b["n"], "t": b["t"], "i": [list(x) for x in b["i"]]}
    a["n"] += b["n"]
    a["t"] += b["t"]
    for x, y in zip(a["i"], b["i"]):
        x[0] += y[0]
        x[1] += y[1]
    return a


def fetch_slot(slot: datetime, cfg: dict, match: list) -> dict | None:
    """Both streams for one slot, or None if either is unavailable (so every stored slot is comparable)."""
    agg = None
    for stream in cfg["media"]["streams"]:
        raw = None
        for minute in (0, 15, 30):  # GDELT occasionally skips a 15-minute file
            stamp = (slot + timedelta(minutes=minute)).strftime("%Y%m%d%H%M%S")
            try:
                raw = get(GDELT.format(stamp=stamp, stream=stream))
                break
            except NotFound:
                continue
        if raw is None:
            return None
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            text = z.read(z.namelist()[0]).decode("utf-8", "replace")
        agg = add(agg, parse_gkg(text, match, cfg["media"]["min_words"]))
    return agg


def slot_key(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H")


def slot_times(start: datetime, end: datetime, hours: list[str]) -> list[datetime]:
    out, d = [], start.date()
    while d <= end.date():
        for h in hours:
            t = datetime(d.year, d.month, d.day, int(h), tzinfo=timezone.utc)
            if start <= t <= end:
                out.append(t)
        d += timedelta(days=1)
    return out


def rnd(x: dict) -> dict:
    return {"n": x["n"], "t": round(x["t"], 1), "i": [[a, round(b, 1)] for a, b in x["i"]]}


def update_media(store: dict, cfg: dict, backfill: int | None) -> tuple[int, list[str]]:
    mc = cfg["media"]
    ids = [i["id"] for i in mc["issues"]]
    match = matchers(cfg)
    media = store.setdefault("media", {})
    if media.get("issues") and media["issues"] != ids:
        # Issue list changed: realign stored arrays by id; new issues start empty.
        old = media["issues"]
        remap = lambda rec: {**rec, "i": [rec["i"][old.index(x)] if x in old else [0, 0.0] for x in ids]}  # noqa: E731
        media["days"] = {k: remap(v) for k, v in media.get("days", {}).items()}
        media["slots"] = {k: remap(v) for k, v in media.get("slots", {}).items()}
    media["issues"] = ids
    days, slots = media.setdefault("days", {}), media.setdefault("slots", {})
    # An issue whose theme list changed gets a fresh history, so old and new definitions never mix.
    defs = {i["id"]: hashlib.sha1(json.dumps(sorted(i["themes"])).encode()).hexdigest()[:10] for i in mc["issues"]}
    changed = [k for k, iid in enumerate(ids) if media.get("defs", {}).get(iid) not in (None, defs[iid])]
    if changed:
        print(f"theme definitions changed for {', '.join(ids[k] for k in changed)}: history reset"
              + ("" if backfill else "; run with --backfill 200 to rebuild it"))
        for rec in list(days.values()) + list(slots.values()):
            for k in changed:
                rec["i"][k] = [0, 0.0]
    media["defs"] = defs

    end = NOW - timedelta(minutes=30)  # translated files land a few minutes after the quarter hour
    if backfill:
        start = datetime.combine(end.date() - timedelta(days=backfill), datetime.min.time(), timezone.utc)
        full = len(mc["slots_utc"])
        todo = [t for t in slot_times(start, end, mc["slots_utc"])
                if changed or (slot_key(t) not in slots
                               and (t.date() >= (end - timedelta(days=SLOT_BUFFER_DAYS)).date()
                                    or days.get(t.date().isoformat(), {}).get("slots", 0) < full))]
        if changed:  # refetch everything; drop stale day sums so they are rebuilt from fresh slots
            for t in todo:
                days.pop(t.date().isoformat(), None)
                slots.pop(slot_key(t), None)
    else:
        start = end - timedelta(days=SLOT_BUFFER_DAYS)
        todo = [t for t in slot_times(start, end, mc["slots_utc"]) if slot_key(t) not in slots]
        todo = todo[-LIVE_MAX_SLOTS:]
    failed: list[str] = []
    fetched = 0
    workers = 4 if backfill else 2
    done_n = 0
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for t, res in zip(todo, ex.map(lambda tt: _safe_slot(tt, cfg, match), todo)):
            done_n += 1
            if isinstance(res, dict):
                slots[slot_key(t)] = rnd(res)
                fetched += 1
            else:
                failed.append(f"{slot_key(t)}: {res}")
            if backfill and done_n % 40 == 0:
                print(f"  {done_n}/{len(todo)} slots", flush=True)
            if backfill and done_n % 200 == 0:  # checkpoint long backfills
                _rebuild_days(days, slots, mc)
                save(store)
    _rebuild_days(days, slots, mc)
    cutoff = (end - timedelta(days=SLOT_BUFFER_DAYS)).date().isoformat()
    for k in [k for k in slots if k[:10] < cutoff]:
        del slots[k]
    for k in sorted(days)[:-DAYS_CAP]:
        del days[k]
    return fetched, failed


def _safe_slot(t, cfg, match):
    try:
        return fetch_slot(t, cfg, match) or "files not published yet"
    except Exception as e:  # noqa: BLE001
        return str(e)[:160]


def _rebuild_days(days: dict, slots: dict, mc: dict) -> None:
    """A day's sums are rebuilt from its slots whenever any of its slots is in the buffer."""
    by_day: dict[str, list] = {}
    for k, v in slots.items():
        by_day.setdefault(k[:10], []).append(v)
    for d, recs in by_day.items():
        if len(recs) < days.get(d, {}).get("slots", 0):
            continue  # never replace a fuller day (e.g. from backfill) with a partial buffer
        agg = None
        for r in recs:
            agg = add(agg, r)
        days[d] = {"slots": len(recs), **rnd(agg)}


def media_summary(store: dict, cfg: dict) -> dict:
    mc = cfg["media"]
    media = store.get("media") or {}
    days = media.get("days") or {}
    if not days:
        return {}
    ids = media["issues"]
    names = {i["id"]: i for i in mc["issues"]}
    last = date.fromisoformat(max(days))
    first = date.fromisoformat(min(days))
    span = (last - first).days + 1
    dates = [first + timedelta(days=k) for k in range(span)]
    rec = [days.get(d.isoformat()) for d in dates]
    W = mc["window_days"]

    def window(end_idx: int) -> dict | None:
        recs = [r for r in rec[max(0, end_idx - W + 1):end_idx + 1] if r]
        if sum(r["slots"] for r in recs) < (W - 2) * len(mc["slots_utc"]):
            return None  # too many missing slots to compare fairly
        agg = None
        for r in recs:
            agg = add(agg, r)
        return agg

    wins = [window(k) for k in range(span)]
    # The headline window ends on the last complete UTC day, so every window holds the same number of
    # samples and weekdays (weekend coverage is lighter and gloomier; a partial day would skew it).
    full = len(mc["slots_utc"])
    cur_idx = next((k for k in range(span - 1, -1, -1) if rec[k] and rec[k]["slots"] >= full), span - 1)
    base_idx = [k for k in range(max(0, cur_idx - W - mc["baseline_days"] + 1), cur_idx - W + 1) if wins[k]]

    def describe(series_fn, share_fn=None) -> dict:
        cur = wins[cur_idx]
        tone = series_fn(cur) if cur else None
        base = [series_fn(wins[k]) for k in base_idx]
        base = [b for b in base if b is not None]
        out: dict = {"tone": None if tone is None else round(tone, 2)}
        if share_fn and cur:
            out["share"] = round(share_fn(cur), 2)
        spark = []
        for k in range(max(0, cur_idx - SPARK_DAYS + 1), cur_idx + 1):
            v = series_fn(wins[k]) if wins[k] else None
            spark.append(None if v is None else round(v, 2))
        out["spark"] = spark
        if tone is None or len(base) < mc["min_baseline"]:
            out.update(band="building", label="Building baseline", baseline=len(base))
            return out
        gloom = round(100 * sum(1 for b in base if b > tone) / len(base))
        key, label = next((k, lb) for lo, k, lb in BANDS if gloom >= lo)
        sd = statistics.pstdev(base) or 1e-9
        prev = wins[cur_idx - W] if cur_idx - W >= 0 else None
        pv = series_fn(prev) if prev else None
        trend = "steady"
        if pv is not None:
            delta = (tone - pv) / sd
            trend = "gloomier" if delta <= -0.5 else "brighter" if delta >= 0.5 else "steady"
        out.update(gloom_pct=gloom, band=key, label=label, trend=trend, baseline=len(base),
                   tone_typical=round(statistics.median(base), 2))
        if share_fn and cur:
            bs = [share_fn(wins[k]) for k in base_idx]
            out["share_pct"] = round(100 * sum(1 for b in bs if b < share_fn(cur)) / len(bs))
            out["share_typical"] = round(statistics.median(bs), 2)
        return out

    def tone_of(k):
        return lambda w: (w["i"][k][1] / w["i"][k][0]) if w and w["i"][k][0] >= 50 else None

    def share_of(k):
        return lambda w: 100 * w["i"][k][0] / w["n"] if w and w["n"] else 0.0

    overall = describe(lambda w: w["t"] / w["n"] if w and w["n"] else None)
    cur = wins[cur_idx] or {}
    as_of = dates[cur_idx].isoformat()
    issues = []
    for k, iid in enumerate(ids):
        if iid not in names:
            continue
        d = describe(tone_of(k), share_of(k))
        issues.append({"id": iid, "name": names[iid]["name"], "domains": names[iid].get("domains", []),
                       "articles": (cur.get("i") or [[0, 0]] * len(ids))[k][0], **d})
    return {
        "as_of": as_of, "window_days": W, "baseline_days": mc["baseline_days"],
        "articles": cur.get("n", 0), "latest_sample": max(media.get("slots") or {"": 0}) or None,
        "spark_start": dates[max(0, cur_idx - SPARK_DAYS + 1)].isoformat(),
        "overall": overall, "issues": issues,
        "source": mc["source"], "source_url": mc["source_url"],
    }


# ───────────────────────── OECD consumer confidence ─────────────────────────

def update_confidence(cfg: dict) -> dict:
    cc = cfg["confidence"]
    areas = cc["areas"]
    key = "+".join(a["id"] for a in areas) + cc["key"]
    raw = get(OECD.format(flow=cc["dataflow"], key=key, since=cc["since"]), timeout=120).decode("utf-8", "replace")
    series: dict[str, list] = {}
    for r in csv.DictReader(io.StringIO(raw)):
        try:
            series.setdefault(r["REF_AREA"], []).append((r["TIME_PERIOD"], float(r["OBS_VALUE"])))
        except (KeyError, ValueError):
            continue
    out = []
    for a in areas:
        s = sorted(series.get(a["id"], []))
        if len(s) < 24:
            continue
        period, v = s[-1]
        vals = [x for _, x in s]
        yago = next((x for p, x in reversed(s) if p <= f"{int(period[:4]) - 1}{period[4:]}"), None)
        band = "above" if v >= 100.5 else "below" if v <= 99.5 else "near"
        out.append({"id": a["id"], "name": a["name"], "value": round(v, 1), "period": period,
                    "chg_1m": round(v - vals[-2], 2), "chg_12m": None if yago is None else round(v - yago, 2),
                    "band": band,
                    # share of months since `since` with higher confidence than now (higher = gloomier)
                    "gloom_pct": round(100 * sum(1 for x in vals[:-1] if x > v) / (len(vals) - 1)),
                    "since": s[0][0]})
    if not out:
        raise RuntimeError("no OECD consumer confidence series returned")
    return {"areas": out, "fetched_at": iso(NOW), "source": cc["source"], "source_url": cc["source_url"],
            "licence": "latest values and derived statistics only"}


# ───────────────────────── entry point ─────────────────────────

def save(store: dict) -> None:
    OUT.write_text(json.dumps(store, ensure_ascii=False, separators=(",", ":")) + "\n")


def main(argv: list[str]) -> int:
    backfill = int(argv[argv.index("--backfill") + 1]) if "--backfill" in argv else None
    cfg = config()
    store = json.loads(OUT.read_text()) if OUT.exists() else {}
    store["version"] = 1
    errors = []
    t0 = time.time()
    try:
        fetched, failed = update_media(store, cfg, backfill)
        print(f"media: {fetched} slots fetched, {len(failed)} unavailable ({time.time() - t0:.0f}s)")
        for f in failed[:8]:
            print(f"  skip {f}")
        if failed and not fetched:
            errors.append(f"media: no new slots ({failed[0]})")
    except Exception as e:  # noqa: BLE001
        errors.append(f"media: {e}"[:200])
        print("FAIL media", e, file=sys.stderr)
    if not backfill or "--with-confidence" in argv:
        try:
            store["confidence"] = update_confidence(cfg)
            print("confidence:", ", ".join(f"{a['id']} {a['value']} ({a['period']})" for a in store["confidence"]["areas"]))
        except Exception as e:  # noqa: BLE001
            errors.append(f"confidence: {e}"[:200])
            if store.get("confidence"):
                store["confidence"]["error"] = str(e)[:200]
            print("FAIL confidence", e, file=sys.stderr)
    store["summary"] = media_summary(store, cfg)
    store["updated_at"] = iso(NOW)
    store["errors"] = errors
    save(store)
    s = store["summary"]
    if s:
        print(f"summary as of {s['as_of']}: overall {s['overall'].get('label')} (tone {s['overall'].get('tone')}, "
              f"{s['articles']} articles in window)")
        for i in s["issues"]:
            print(f"  {i['id']:10} {i.get('label', ''):26} tone {i.get('tone')} share {i.get('share')}% "
                  f"gloom_pct {i.get('gloom_pct')} share_pct {i.get('share_pct')} trend {i.get('trend')}")
    # A failed source keeps its previous data; only a run with nothing usable at all is an error.
    return 0 if store.get("summary") or store.get("confidence") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
