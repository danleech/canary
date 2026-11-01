#!/usr/bin/env python3
"""Canary pipeline: plan a run, apply assessed updates, validate, and build derived files.

  python scripts/canary.py plan            # what is due this run + metric-based suggestions
  python scripts/canary.py apply FILE      # merge an updates JSON into status, then build + check
  python scripts/canary.py build           # rebuild derived files (catalogue.json, world index, feed)
  python scripts/canary.py check           # validate everything; non-zero exit on any error

Data files (all under site/data/):
  status.json    current state of every signal (written only via `apply`)
  history.json   per-signal status/value timeline
  changes.json   log of status changes (feeds the Atom feed and 'changed in 24h')
  runs.json      log of assessment runs
  metrics.json   hard numbers from scripts/fetch_metrics.py
  catalogue.json generated from signals/catalogue.yaml for the site
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.sax.saxutils import escape

import yaml

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "site" / "data"
CATALOGUE = ROOT / "signals" / "catalogue.yaml"
SITE_URL = "https://canary.danleech.com"  # Cloudflare Pages custom domain

LEVEL = {"green": 0, "amber": 1, "red": 2}
NAME = {0: "green", 1: "amber", 2: "red"}
LABEL = {"green": "Normal", "amber": "Watch", "red": "Alert"}
TRENDS = {"up", "flat", "down"}
FAST_STALE_H, DAILY_STALE_H, DAILY_DUE_H = 14, 36, 20
HISTORY_CAP, CHANGES_CAP, RUNS_CAP = 240, 400, 200
ADVICE_DOMAINS = {"markets", "economy", "energy", "uk"}
BANNED = re.compile(
    r"\b(buy|sell(?![- ]?off)|switch (?:to|into|out of|your)|move (?:your )?(?:money|assets|savings|pension)"
    r"|invest in|divest|go long|go short|short (?:the|selling)|take profits?|rebalanc\w*|you should (?:buy|sell|invest))\b",
    re.I,
)
LIMITS = {"value": 48, "summary": 120, "state": 700, "for_you": 320}


def now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse(ts: str | None) -> datetime | None:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def load(name: str, default):
    p = DATA / name
    if p.exists():
        return json.loads(p.read_text())
    return default


def save(name: str, obj) -> None:
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / name).write_text(json.dumps(obj, indent=1, ensure_ascii=False) + "\n")


def catalogue() -> dict:
    return yaml.safe_load(CATALOGUE.read_text())


# ───────────────────────── metric-based suggestions ─────────────────────────
# Each rule: (label, value, amber_threshold, red_threshold). Higher value = worse.
# Hysteresis: to step DOWN from the previous status, the value must clear the
# threshold by MARGIN (e.g. VIX must fall below 27, not 30, to leave red).
MARGIN = 0.10


def _level(v, a, r, shrink=0.0):
    if v is None:
        return None
    a2, r2 = a * (1 - shrink), r * (1 - shrink)
    return 2 if v > r2 else 1 if v >= a2 else 0


def _m(metrics, key, field="value"):
    m = metrics.get(key) or {}
    return m.get(field)


def _abs(x):
    return None if x is None else abs(x)


def suggest(sig_id: str, metrics: dict, prev_level: int | None) -> dict | None:
    """Return {'status','value','value_num','basis'} or None if no metric rule applies."""
    M = lambda k, f="value": _m(metrics, k, f)  # noqa: E731
    rules: list[tuple] = []
    triggers: list[tuple[int, str]] = []  # hard triggers that set a minimum level
    value = num = None

    if sig_id == "equity-stress":
        vix, dd = M("vix"), M("spx", "drawdown_pct")
        rules = [("VIX", vix, 20, 30), ("S&P drawdown %", _abs(dd), 5, 15)]
        value, num = (f"VIX {vix:.1f}, S&P {dd:+.1f}%" if vix is not None and dd is not None else None), vix
    elif sig_id == "ftse":
        dd, worst = M("ftse", "drawdown_pct"), M("ftse", "worst_day_5d_pct")
        rules = [("FTSE drawdown %", _abs(dd), 5, 12)]
        if worst is not None and worst < -4:
            triggers.append((2, f"single-day fall {worst:.1f}%"))
        elif worst is not None and worst < -2.5:
            triggers.append((1, f"single-day fall {worst:.1f}%"))
        v = M("ftse")
        value, num = (f"{v:,.0f}, {dd:+.1f}% from high" if v and dd is not None else None), v
    elif sig_id == "bond-volatility":
        mv, chg = M("move"), M("us10y", "chg_1m_abs")
        bp = _abs(chg * 100) if chg is not None else None
        rules = [("MOVE", mv, 100, 140), ("US10y 1m move bp", bp, 40, 1e9)]
        y = M("us10y")
        value, num = (f"MOVE {mv:.0f}, 10y {y:.2f}%" if mv and y else None), mv
    elif sig_id == "credit-spreads":
        v, chg = M("hy_oas"), M("hy_oas", "chg_1m_abs")
        rules = [("HY OAS %", v, 4.0, 6.0)]
        if chg is not None and chg * 100 > 200:
            triggers.append((2, f"+{chg*100:.0f}bp in a month"))
        elif chg is not None and chg * 100 > 100:
            triggers.append((1, f"+{chg*100:.0f}bp in a month"))
        value, num = (f"HY OAS {v:.2f}%" if v is not None else None), v
    elif sig_id == "dollar":
        v, c3 = M("dxy"), M("dxy", "chg_3m_pct")
        rules = [("DXY 3m move %", _abs(c3), 5, 8)]
        if v is not None and not 90 <= v <= 108:
            triggers.append((1, f"DXY {v:.1f} outside 90–108"))
        value, num = (f"DXY {v:.1f}, 3m {c3:+.1f}%" if v and c3 is not None else None), v
    elif sig_id == "banking-stress":
        v = M("stlfsi")
        rules = [("STLFSI", v, 0.0, 1.5)]  # amber at ≥ 0
        value, num = (f"STLFSI {v:+.2f}" if v is not None else None), v
    elif sig_id == "gold":
        v, c3, s = M("gold"), M("gold", "chg_3m_pct"), M("gold", "series") or []
        wk = (s[-1] / s[-6] - 1) * 100 if len(s) > 6 else None
        rules = [("Gold 3m gain %", c3 if c3 is not None else None, 10, 20)]
        if c3 is not None and c3 < -8:
            triggers.append((1, f"3m fall {c3:.1f}%"))
        if wk is not None and abs(wk) > 7:
            triggers.append((2, f"1w move {wk:+.1f}%"))
        value, num = (f"${v:,.0f}, 3m {c3:+.1f}%" if v and c3 is not None else None), v
    elif sig_id == "crypto":
        v, dd = M("btc"), M("btc", "drawdown_pct")
        rules = [("BTC drawdown %", _abs(dd), 25, 45)]
        value, num = (f"BTC ${v:,.0f}, {dd:+.0f}% from high" if v and dd is not None else None), v
    elif sig_id == "us-recession":
        v = M("sahm")
        rules = [("Sahm", v, 0.30, 0.4999)]
        t = M("t10y2y")
        value, num = (f"Sahm {v:.2f}, 10y–2y {t:+.2f}" if v is not None and t is not None else None), v
    elif sig_id == "us-inflation":
        v = M("us_cpi")
        rules = [("CPI y/y %", v, 3.0, 4.5)]
        if M("us_cpi", "rising_3m"):
            triggers.append((1, "rising 3 months"))
        value, num = (f"CPI {v:.1f}% y/y" if v is not None else None), v
    elif sig_id == "oil":
        v, c1 = M("brent"), M("brent", "chg_1m_pct")
        rules = [("Brent $", v, 85, 110), ("Brent 1m %", c1, 15, 30)]
        value, num = (f"${v:.1f}, 1m {c1:+.0f}%" if v and c1 is not None else None), v
    elif sig_id == "eu-gas":
        v = M("ttf")
        rules = [("TTF €/MWh", v, 40, 70)]
        value, num = (f"€{v:.0f}/MWh" if v else None), v
    elif sig_id == "earthquakes":
        q = metrics.get("quakes") or {}
        pager = {"orange": 1, "red": 2}.get(q.get("max_pager"), 0)
        if pager:
            triggers.append((pager, f"PAGER {q.get('max_pager')}"))
        if (q.get("count_m7") or 0) > 0:
            triggers.append((1, f"{q['count_m7']}× M7+ this week"))
        rules = [("max magnitude", q.get("value"), 7.0, 99)]
        value, num = (f"Max M{q['value']:.1f}, {q.get('count_m6', 0)}× M6+ (7d)" if q.get("value") else None), q.get("value")
    elif sig_id == "space-weather":
        s = metrics.get("swpc") or {}
        g, ss, r = s.get("G_24h"), s.get("S_24h"), s.get("R_24h")
        if g is not None:
            lvl = max(2 if g >= 4 else 1 if g >= 3 else 0, 2 if ss >= 3 else 1 if ss >= 2 else 0,
                      2 if r >= 4 else 1 if r >= 3 else 0)
            triggers.append((lvl, f"NOAA G{g} S{ss} R{r} (24h max)"))
            value, num = f"G{g} S{ss} R{r}", g
    elif sig_id == "global-temp":
        v = M("global_temp")
        rules = [("°C above pre-industrial", v, 1.3, 1.6)]
        if M("global_temp", "record_for_date"):
            triggers.append((2, "record for date"))
        value, num = (f"+{v:.2f}°C vs pre-industrial" if v is not None else None), v
    elif sig_id == "sea-ice":
        si = metrics.get("sea_ice") or {}
        a, b = (si.get("arctic") or {}), (si.get("antarctic") or {})
        worst = min([x for x in (a.get("anomaly"), b.get("anomaly")) if x is not None], default=None)
        if worst is not None:
            triggers.append((1 if worst < -1.0 else 0, f"worst anomaly {worst:+.2f}M km²"))
        if a.get("record_low_for_date") or b.get("record_low_for_date"):
            triggers.append((2, "record low for date"))
        if a.get("anomaly") is not None and b.get("anomaly") is not None:
            value, num = f"Arctic {a['anomaly']:+.2f}, Antarctic {b['anomaly']:+.2f}M km²", worst
    elif sig_id == "co2":
        y = M("co2", "yoy_ppm")
        rules = [("CO₂ y/y ppm", y, 2.0, 3.0)]
        v = M("co2")
        value, num = (f"{v:.1f} ppm, +{y:.2f}/yr" if v and y is not None else None), v
    elif sig_id == "enso":
        v = M("oni")
        rules = [("|ONI|", _abs(v), 0.5, 1.4999)]
        value, num = (f"ONI {v:+.1f} ({M('oni','phase')})" if v is not None else None), v
    elif sig_id == "uk-weather":
        w = M("metoffice")
        if w:
            triggers.append(({"red": 2, "amber": 1}.get(w, 0), f"worst warning: {w}"))
            c = M("metoffice", "counts") or {}
            value = "No warnings" if w == "none" else f"{sum(c.values())} warning(s), worst {w}"
    elif sig_id in ("atlantic-cyclones", "other-cyclones", "wildfires", "floods"):
        t = {"atlantic-cyclones": "cyclone", "other-cyclones": "cyclone", "wildfires": "wildfire", "floods": "flood"}[sig_id]
        bt = ((metrics.get("gdacs") or {}).get("by_type") or {}).get(t) or {}
        if sig_id != "atlantic-cyclones" and bt:  # GDACS is global; Atlantic needs NHC context
            lvl = 2 if bt.get("red") else 1 if bt.get("orange") else 0
            triggers.append((lvl, f"GDACS {t}: {bt.get('red',0)} red / {bt.get('orange',0)} orange"))
    else:
        return None

    levels, basis = [], []
    for label, v, a, r in rules:
        lv = _level(v, a, r)
        if lv is None:
            continue
        if prev_level is not None and lv < prev_level:
            lv = min(prev_level, max(lv, _level(v, a, r, MARGIN)))
        levels.append(lv)
        basis.append(f"{label}={v:.2f}" if isinstance(v, (int, float)) else f"{label}={v}")
    for lv, why in triggers:
        levels.append(lv)
        basis.append(why)
    if not levels:
        return None
    return {"status": NAME[max(levels)], "value": value, "value_num": num, "basis": "; ".join(basis)}


# ───────────────────────── plan ─────────────────────────

def due(sig: dict, cur: dict | None, t: datetime) -> bool:
    if sig["tier"] == "fast" or not cur:
        return True
    last = parse(cur.get("checked_at"))
    return last is None or (t - last) > timedelta(hours=DAILY_DUE_H)


def cmd_plan(_args) -> int:
    cat, status, metrics = catalogue(), load("status.json", {}), load("metrics.json", {}).get("metrics", {})
    sigs, t = status.get("signals", {}), now()
    mfetch = parse(load("metrics.json", {}).get("fetched_at"))
    print(f"# Canary run plan — {iso(t)}")
    print(f"metrics fetched: {iso(mfetch) if mfetch else 'never'}"
          + ("  ⚠ older than 3h — run scripts/fetch_metrics.py" if not mfetch or t - mfetch > timedelta(hours=3) else ""))
    todo, carry = [], []
    for s in cat["signals"]:
        (todo if due(s, sigs.get(s["id"]), t) else carry).append(s)
    print(f"due: {len(todo)}   carried forward (daily, fresh): {len(carry)}\n")
    dom = None
    for s in todo:
        if s["domain"] != dom:
            dom = s["domain"]
            print(f"\n## {dom}")
        cur = sigs.get(s["id"]) or {}
        sug = suggest(s["id"], metrics, LEVEL.get(cur.get("status")))
        line = f"- {s['id']} [{s['tier']}] prev={cur.get('status','—')} {cur.get('value','')!s}"
        if sug:
            line += f"\n    metric floor → {sug['status'].upper()}  value='{sug['value']}'  ({sug['basis']})"
        print(line)
    if carry:
        print("\n## carried forward\n" + ", ".join(s["id"] for s in carry))
    return 0


# ───────────────────────── apply ─────────────────────────

def cmd_apply(args) -> int:
    if not args:
        print("usage: canary.py apply UPDATES.json", file=sys.stderr)
        return 2
    upd = json.loads(Path(args[0]).read_text())
    cat = catalogue()
    by_id = {s["id"]: s for s in cat["signals"]}
    status = load("status.json", {"signals": {}})
    history = load("history.json", {})
    changes = load("changes.json", [])
    runs = load("runs.json", [])
    metrics = load("metrics.json", {}).get("metrics", {})
    sigs = status.setdefault("signals", {})
    t = now()
    warnings, applied, changed = [], 0, []

    for u in upd.get("signals", []):
        sid = u.get("id")
        if sid not in by_id:
            warnings.append(f"unknown signal id '{sid}' — skipped")
            continue
        prev = sigs.get(sid) or {}
        prev_lvl = LEVEL.get(prev.get("status"))
        new = {**prev, **{k: v for k, v in u.items() if k not in ("id", "override_reason")}}
        lvl = LEVEL.get(new.get("status"))
        if lvl is None:
            warnings.append(f"{sid}: invalid status '{new.get('status')}' — skipped")
            continue
        sug = suggest(sid, metrics, prev_lvl)
        override = u.get("override_reason")
        # metric floor: an assessment may raise a metric-based status but not lower it without a reason
        if sug and LEVEL[sug["status"]] > lvl and not override:
            warnings.append(f"{sid}: raised {NAME[lvl]}→{sug['status']} to metric floor ({sug['basis']})")
            lvl = LEVEL[sug["status"]]
        # one-step rule: no green↔red jump in a single run unless a metric/hard trigger or override says so
        if prev_lvl is not None and abs(lvl - prev_lvl) == 2 and not override and not (sug and LEVEL[sug["status"]] == lvl):
            warnings.append(f"{sid}: clamped {NAME[prev_lvl]}→{NAME[lvl]} to amber (one-step rule; add override_reason)")
            lvl = 1
        new["status"] = NAME[lvl]
        if sug and not u.get("value") and sug.get("value"):
            new["value"] = sug["value"]
        if sug and new.get("value_num") is None and sug.get("value_num") is not None:
            new["value_num"] = sug["value_num"]
        if override:
            new["override_reason"] = override
        else:
            new.pop("override_reason", None)
        new["checked_at"] = iso(t)
        if prev_lvl != lvl:
            new["changed_at"] = iso(t)
            if prev_lvl is not None:
                changes.insert(0, {"t": iso(t), "id": sid, "name": by_id[sid]["name"],
                                   "from": NAME[prev_lvl], "to": NAME[lvl], "reason": new.get("summary", "")})
                changed.append(sid)
        new.setdefault("changed_at", iso(t))
        sigs[sid] = new
        h = history.setdefault(sid, [])
        h.append([iso(t), new["status"][0], new.get("value_num")])
        del h[:-HISTORY_CAP]
        applied += 1

    run = upd.get("run", {})
    if run.get("headline"):
        status["headline"] = run["headline"]
    status["generated_at"] = iso(t)
    status["world"] = world_index(cat, sigs)
    runs.insert(0, {"t": iso(t), "applied": applied, "changed": changed, "warnings": warnings,
                    "note": run.get("note", "")})
    save("status.json", status)
    save("history.json", history)
    save("changes.json", changes[:CHANGES_CAP])
    save("runs.json", runs[:RUNS_CAP])
    for w in warnings:
        print("WARN", w)
    print(f"applied {applied} signal updates; {len(changed)} status changes: {', '.join(changed) or '—'}")
    cmd_build([])
    return cmd_check([])


# ───────────────────────── build ─────────────────────────

def world_index(cat: dict, sigs: dict) -> dict:
    num = den = 0.0
    counts = {"green": 0, "amber": 0, "red": 0}
    by_dom = {}
    for d in cat["domains"]:
        pts = [LEVEL[sigs[s["id"]]["status"]] for s in cat["signals"]
               if s["domain"] == d["id"] and sigs.get(s["id"], {}).get("status") in LEVEL]
        if not pts:
            continue
        mean = sum(pts) / len(pts)
        by_dom[d["id"]] = round(mean / 2 * 100)
        num += d["weight"] * mean
        den += d["weight"] * 2
    for s in sigs.values():
        if s.get("status") in counts:
            counts[s["status"]] += 1
    score = round(num / den * 100) if den else None
    band = (None if score is None else "Calm" if score < 25 else "Unsettled" if score < 40
            else "Strained" if score < 60 else "Severe")
    colour = None if score is None else "green" if score < 25 else "amber" if score < 60 else "red"
    return {"score": score, "band": band, "status": colour, "counts": counts, "by_domain": by_dom}


def cmd_build(_args) -> int:
    cat = catalogue()
    save("catalogue.json", cat)
    status = load("status.json", {"signals": {}})
    status["world"] = world_index(cat, status.get("signals", {}))
    save("status.json", status)
    changes = load("changes.json", [])
    feed_updated = changes[0]["t"] if changes else status.get("generated_at") or iso(now())
    entries = []
    for c in changes[:60]:
        title = f"{c['name']}: {LABEL[c['from']]} → {LABEL[c['to']]}"
        entries.append(
            f"  <entry>\n    <title>{escape(title)}</title>\n"
            f"    <id>tag:canary,{c['t'][:10]}:{c['id']}:{c['t']}</id>\n"
            f"    <updated>{c['t']}</updated>\n"
            f"    <link href=\"{SITE_URL}/#{c['id']}\"/>\n"
            f"    <summary>{escape(c.get('reason') or '')}</summary>\n  </entry>")
    feed = ("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
            "  <title>Canary — status changes</title>\n"
            f"  <link href=\"{SITE_URL}/\"/>\n  <link rel=\"self\" href=\"{SITE_URL}/feed.xml\"/>\n"
            f"  <id>{SITE_URL}/</id>\n  <updated>{feed_updated}</updated>\n"
            "  <author><name>Canary</name></author>\n" + "\n".join(entries) + "\n</feed>\n")
    (ROOT / "site" / "feed.xml").write_text(feed)
    print("built catalogue.json, world index, feed.xml")
    return 0


# ───────────────────────── check ─────────────────────────

def cmd_check(_args) -> int:
    errs, warns = [], []
    cat = catalogue()
    dom_ids = {d["id"] for d in cat["domains"]}
    ids = [s["id"] for s in cat["signals"]]
    if len(ids) != len(set(ids)):
        errs.append("duplicate signal ids in catalogue")
    for s in cat["signals"]:
        for k in ("id", "domain", "name", "tier", "why", "drivers", "rubric"):
            if not s.get(k):
                errs.append(f"catalogue {s.get('id')}: missing {k}")
        if s.get("domain") not in dom_ids:
            errs.append(f"catalogue {s['id']}: unknown domain {s.get('domain')}")
        if s.get("tier") not in ("fast", "daily"):
            errs.append(f"catalogue {s['id']}: tier must be fast|daily")
        if set((s.get("rubric") or {}).keys()) != {"green", "amber", "red"}:
            errs.append(f"catalogue {s['id']}: rubric needs green/amber/red")
    status = load("status.json", {"signals": {}})
    sigs = status.get("signals", {})
    by_id = {s["id"]: s for s in cat["signals"]}
    for sid, s in sigs.items():
        if sid not in by_id:
            errs.append(f"status: '{sid}' not in catalogue")
            continue
        if s.get("status") not in LEVEL:
            errs.append(f"{sid}: bad status {s.get('status')}")
        if s.get("trend") not in TRENDS:
            errs.append(f"{sid}: trend must be up|flat|down")
        for f in ("summary", "state", "for_you"):
            if not s.get(f):
                errs.append(f"{sid}: missing {f}")
        if not s.get("value"):
            warns.append(f"{sid}: no value (the board shows an empty Reading cell)")
        for f, lim in LIMITS.items():
            if s.get(f) and len(s[f]) > lim:
                errs.append(f"{sid}: {f} is {len(s[f])} chars (max {lim})")
        srcs = s.get("sources") or []
        if not srcs:
            errs.append(f"{sid}: no sources")
        for src in srcs:
            if not re.match(r"https?://", src.get("url", "")) or not src.get("title"):
                errs.append(f"{sid}: bad source {src}")
        if not parse(s.get("checked_at")):
            errs.append(f"{sid}: bad checked_at")
        if by_id[sid]["domain"] in ADVICE_DOMAINS:
            for f in ("summary", "state", "for_you"):
                m = BANNED.search(s.get(f) or "")
                if m:
                    errs.append(f"{sid}: advice-like phrase '{m.group(0)}' in {f} (finance copy must be descriptive)")
    missing = [i for i in ids if i not in sigs]
    if missing:
        warns.append(f"{len(missing)} catalogue signals not yet assessed: {', '.join(missing[:8])}…")
    for w in warns:
        print("warn:", w)
    for e in errs:
        print("ERROR:", e)
    print(f"check: {len(errs)} errors, {len(warns)} warnings, {len(sigs)}/{len(ids)} signals assessed")
    return 1 if errs else 0


if __name__ == "__main__":
    cmds = {"plan": cmd_plan, "apply": cmd_apply, "build": cmd_build, "check": cmd_check}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print(__doc__)
        sys.exit(2)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))
