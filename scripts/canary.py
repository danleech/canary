#!/usr/bin/env python3
"""Canary pipeline: plan a run, apply assessed updates, validate, and build derived files.

  python scripts/canary.py plan            # what is due this run + metric-based suggestions
  python scripts/canary.py apply FILE      # merge an updates JSON into status, then build + check
  python scripts/canary.py build           # rebuild derived files (catalogue, world index, feed, agent outputs, pages)
  python scripts/canary.py check           # validate everything; non-zero exit on any error

Data files (all under site/data/):
  status.json    current state of every signal (written only via `apply`)
  history.json   per-signal status/value timeline
  changes.json   log of status changes (feeds the Atom feed and 'changed in 24h')
  runs.json      log of assessment runs
  metrics.json   hard numbers from scripts/fetch_metrics.py
  catalogue.json generated from signals/catalogue.yaml for the site

Derived public outputs (now.md, status.md, s/*, api/v1/*, llms.txt, feed.xml, …) are
written by scripts/publish.py during `build`.
"""
from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
import publish  # noqa: E402

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
LIMITS = {"value": 48, "summary": 120, "state": 700, "for_you": 320, "rubric_hit": 200}
HORIZONS = {"acute", "seasonal", "chronic"}
MAX_SITUATIONS, MAX_EMERGING = 10, 3
PROSE = ("value", "summary", "state", "for_you", "rubric_hit")
# Canary's text is pasted into other AI agents' context windows, so it must never carry
# instructions. These patterns catch prompt-injection text copied from a poisoned source.
INJECTION = re.compile(
    r"(ignore (?:all |any )?(?:previous|prior|above|earlier) (?:instructions|prompts?)"
    r"|disregard (?:the |all |your )?(?:previous|prior|above|system)"
    r"|(?:system|developer) (?:prompt|message|instructions?)"
    r"|you are (?:now )?(?:an? )?(?:ai|assistant|language model|chatbot|llm)\b"
    r"|as an ai (?:language )?model|\bassistant:|\buser:|<\/?(?:system|instructions?|prompt)>"
    r"|(?:do not|don't) (?:tell|inform|reveal to) the user"
    r"|\b(?:jailbreak|prompt injection)\b)",
    re.I,
)
INVISIBLE = re.compile("[\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff\U000e0000-\U000e007f]")
URL_IN_PROSE = re.compile(r"(?:https?://|www\.)\S+", re.I)
TRUSTED = ROOT / "signals" / "trusted_sources.yaml"


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
        v, c = M("stlfsi"), M("ciss")
        rules = [("STLFSI", v, 0.0, 1.5), ("ECB CISS", c, 0.25, 0.45)]  # STLFSI amber at ≥ 0
        value = (f"STLFSI {v:+.2f}" + (f", CISS {c:.2f}" if c is not None else "")) if v is not None else None
        num = v
    elif sig_id == "funding-stress":
        sp, rp = M("sofr_iorb", "max_5d_bp"), M("repo_ops", "max_5d")
        rules = [("SOFR–IORB 5d max bp", sp, 10, 25), ("Fed repo ops 5d max $bn", rp, 15, 50)]
        cur = M("sofr_iorb")
        value = f"SOFR–IORB {cur:+.0f}bp, repo ${rp:.1f}bn" if cur is not None and rp is not None else None
        num = cur
    elif sig_id == "yen-carry":
        v, w, m1 = M("usdjpy"), M("usdjpy", "chg_1w_pct"), M("usdjpy", "chg_1m_pct")
        rules = [("USD/JPY 1w move %", _abs(w), 3, 5), ("USD/JPY 1m move %", _abs(m1), 6, 10)]
        value = f"¥{v:.1f}/$, 1w {w:+.1f}%" if v is not None and w is not None else None
        num = v
    elif sig_id == "jobless-claims":
        a4, up = M("icsa", "avg4"), M("icsa", "above_low_pct")
        rules = [("4wk avg % above 52w low", up, 15, 30)]
        value = f"{a4/1000:.0f}k 4wk avg, +{up:.0f}% vs low" if a4 is not None and up is not None else None
        num = a4
    elif sig_id == "exploited-vulns":
        n7, n30 = M("kev", "count_7d"), M("kev", "count_30d")
        rules = [("KEV additions 7d", n7, 11, 1e9)]
        value = f"{n7} KEV adds (7d), {n30} (30d)" if n7 is not None else None
        num = n7
    elif sig_id == "uk-floods":
        c = M("ea_floods", "counts") or {}
        if c:
            sev, warn = c.get("severe", 0), c.get("warning", 0)
            triggers.append((2 if sev else 1 if warn >= 10 else 0, f"EA: {sev} severe, {warn} warnings"))
            value = "No flood warnings" if not (sev or warn) else f"{sev} severe, {warn} flood warnings"
            num = warn
    elif sig_id == "gold":
        v, c3, wk = M("gold"), M("gold", "chg_3m_pct"), M("gold", "chg_1w_pct")
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
    print(f"due: {len(todo)}   carried forward (daily, fresh): {len(carry)}")
    anchors = []
    for key, label in (("gpr", "Geopolitical Risk index (7d avg)"), ("epu", "US policy uncertainty (7d avg)"),
                       ("ciss", "ECB systemic stress"), ("gas_storage", "EU gas storage % full")):
        m = metrics.get(key) or {}
        if m.get("value") is not None:
            rel = f", {m['vs_1y_median']}× its 1-year median" if m.get("vs_1y_median") else ""
            anchors.append(f"  {label}: {m['value']}{rel} (as of {m.get('as_of')})")
    if anchors:
        print("context anchors (inform judgement; not floors):\n" + "\n".join(anchors))
    print()
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
    bad = validate_updates(upd, by_id)
    if bad:  # reject before touching any data file, so a fixed file can simply be re-applied
        for e in bad:
            print("ERROR:", e)
        print(f"apply aborted: {len(bad)} problem(s) in {args[0]}; nothing was written")
        return 1
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
    if "situations" in run:  # replaces the whole list; omit the key to keep the previous one
        status["situations"] = [
            {k: s.get(k) for k in ("id", "name", "status", "trend", "summary", "signals")}
            for s in (run.get("situations") or [])][:MAX_SITUATIONS]
    if "emerging" in run:
        status["emerging"] = [
            {k: x.get(k) for k in ("name", "status", "summary", "sources", "first_seen") if x.get(k) is not None}
            for x in (run.get("emerging") or [])][:MAX_EMERGING]
    if applied:
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
    written = publish.build(SITE_URL, cat, status, load("changes.json", []), load("history.json", {}),
                            load("metrics.json", {}).get("metrics", {}),
                            {"fast": FAST_STALE_H, "daily": DAILY_STALE_H})
    print(f"built catalogue.json, world index and public outputs ({len(written)} files changed)")
    return 0


# ───────────────────────── check ─────────────────────────

def validate_updates(upd: dict, by_id: dict) -> list[str]:
    """Structural and safety checks on an updates file, run before anything is merged."""
    errs: list[str] = []
    run = upd.get("run") or {}
    if run.get("headline"):
        check_text("run.headline", {"headline": run["headline"]}, errs, limit=260)
        m = BANNED.search(run["headline"])
        if m:
            errs.append(f"run.headline: advice-like phrase '{m.group(0)}' (the headline must stay descriptive)")
    for x in run.get("situations") or []:
        xid = x.get("id") or "?"
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", xid):
            errs.append(f"situation '{xid}': id must be kebab-case")
        if x.get("status") not in LEVEL or x.get("trend") not in TRENDS:
            errs.append(f"situation {xid}: status must be green|amber|red and trend up|flat|down")
        unknown = [i for i in x.get("signals") or [] if i not in by_id]
        if not x.get("signals") or unknown:
            errs.append(f"situation {xid}: needs signal ids from the catalogue (unknown: {unknown})")
        check_text(f"situation {xid}", {"name": x.get("name")}, errs, limit=60, required=True)
        check_text(f"situation {xid}", {"summary": x.get("summary")}, errs, limit=160, required=True)
    if len(run.get("situations") or []) > MAX_SITUATIONS:
        errs.append(f"run.situations: max {MAX_SITUATIONS}")
    for x in run.get("emerging") or []:
        nm = x.get("name") or "?"
        if x.get("status") not in ("amber", "red"):
            errs.append(f"emerging '{nm}': status must be amber or red (otherwise leave it out)")
        check_text(f"emerging '{nm}'", {"name": x.get("name")}, errs, limit=60, required=True)
        check_text(f"emerging '{nm}'", {"summary": x.get("summary")}, errs, limit=160, required=True)
        if not x.get("sources"):
            errs.append(f"emerging '{nm}': no sources")
        check_sources(f"emerging '{nm}'", x.get("sources") or [], set(), errs, {})
    if len(run.get("emerging") or []) > MAX_EMERGING:
        errs.append(f"run.emerging: max {MAX_EMERGING}")
    for u in upd.get("signals", []):
        sid = u.get("id", "?")
        if sid in by_id:
            check_text(sid, {f: u.get(f) for f in PROSE}, errs)
            check_sources(sid, u.get("sources") or [], set(), errs, {})
    return errs


def check_text(where: str, fields: dict, errs: list, limit: int | None = None, required: bool = False) -> None:
    """Prose that other AI agents will read: no instructions, no hidden characters, no inline URLs."""
    for f, v in fields.items():
        if v is None or v == "":
            if required:
                errs.append(f"{where}: missing {f}")
            continue
        if not isinstance(v, str):
            errs.append(f"{where}: {f} must be text")
            continue
        if limit and len(v) > limit:
            errs.append(f"{where}: {f} is {len(v)} chars (max {limit})")
        if INVISIBLE.search(v):
            errs.append(f"{where}: invisible or bidi control characters in {f}")
        m = INJECTION.search(v)
        if m:
            errs.append(f"{where}: instruction-like text '{m.group(0)}' in {f} (possible prompt injection from a source)")
        if URL_IN_PROSE.search(v):
            errs.append(f"{where}: URL in {f} (put links in sources, not in prose)")


def check_sources(where: str, srcs: list, trusted: set, errs: list, untrusted: dict) -> None:
    for src in srcs:
        url = src.get("url", "")
        if not re.match(r"https?://", url) or not src.get("title"):
            errs.append(f"{where}: bad source {src}")
            continue
        check_text(where, {"source title": src.get("title")}, errs, limit=200)
        host = re.sub(r"^www\.", "", url.split("/")[2].split(":")[0].lower())
        if trusted and not any(host == d or host.endswith("." + d) for d in trusted):
            untrusted.setdefault(host, set()).add(where)


def trusted_domains() -> set:
    if not TRUSTED.exists():
        return set()
    return {d.lower().strip() for d in (yaml.safe_load(TRUSTED.read_text()) or {}).get("domains", [])}


def cmd_check(_args) -> int:
    errs, warns = [], []
    cat = catalogue()
    trusted, untrusted = trusted_domains(), {}
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
        if s.get("horizon", "acute") not in HORIZONS:
            errs.append(f"catalogue {s['id']}: horizon must be acute|seasonal|chronic")
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", s.get("id") or ""):
            errs.append(f"catalogue {s.get('id')}: id must be kebab-case")
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
        check_sources(sid, srcs, trusted, errs, untrusted)
        check_text(sid, {f: s.get(f) for f in PROSE}, errs)
        if not parse(s.get("checked_at")):
            errs.append(f"{sid}: bad checked_at")
        if by_id[sid]["domain"] in ADVICE_DOMAINS:
            for f in ("summary", "state", "for_you"):
                m = BANNED.search(s.get(f) or "")
                if m:
                    errs.append(f"{sid}: advice-like phrase '{m.group(0)}' in {f} (finance copy must be descriptive)")
    if status.get("headline"):
        check_text("headline", {"headline": status["headline"]}, errs, limit=260)
        m = BANNED.search(status["headline"])
        if m:
            errs.append(f"headline: advice-like phrase '{m.group(0)}' (the headline must stay descriptive)")
    sits = status.get("situations") or []
    if len(sits) > MAX_SITUATIONS:
        errs.append(f"situations: {len(sits)} listed (max {MAX_SITUATIONS})")
    seen = set()
    for x in sits:
        xid = x.get("id") or "?"
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", xid) or xid in seen:
            errs.append(f"situation '{xid}': id must be unique kebab-case")
        seen.add(xid)
        if x.get("status") not in LEVEL:
            errs.append(f"situation {xid}: bad status {x.get('status')}")
        if x.get("trend") not in TRENDS:
            errs.append(f"situation {xid}: trend must be up|flat|down")
        if not x.get("name") or len(x["name"]) > 60:
            errs.append(f"situation {xid}: name missing or over 60 chars")
        unknown = [i for i in x.get("signals") or [] if i not in by_id]
        if not x.get("signals") or unknown:
            errs.append(f"situation {xid}: needs signal ids from the catalogue (unknown: {unknown})")
        check_text(f"situation {xid}", {"summary": x.get("summary")}, errs, limit=160, required=True)
    emer = status.get("emerging") or []
    if len(emer) > MAX_EMERGING:
        errs.append(f"emerging: {len(emer)} listed (max {MAX_EMERGING})")
    for x in emer:
        nm = x.get("name") or "?"
        if x.get("status") not in ("amber", "red"):
            errs.append(f"emerging '{nm}': status must be amber or red (otherwise leave it out)")
        if not x.get("name") or len(x["name"]) > 60:
            errs.append(f"emerging '{nm}': name missing or over 60 chars")
        check_text(f"emerging '{nm}'", {"summary": x.get("summary")}, errs, limit=160, required=True)
        if not x.get("sources"):
            errs.append(f"emerging '{nm}': no sources")
        check_sources(f"emerging '{nm}'", x.get("sources") or [], trusted, errs, untrusted)
    if untrusted:
        warns.append(f"{len(untrusted)} source domain(s) not in signals/trusted_sources.yaml (prefer established "
                     "outlets; add a domain only after checking it): "
                     + "; ".join(f"{h} ({', '.join(sorted(w))})" for h, w in sorted(untrusted.items())))
    for name, budget in (("now.md", 1600), ("status.md", 4500)):
        f = ROOT / "site" / name
        if f.exists() and publish.est_tokens(f.read_text()) > budget:
            warns.append(f"{name} is ~{publish.est_tokens(f.read_text())} tokens (budget {budget}); tighten summaries")
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
