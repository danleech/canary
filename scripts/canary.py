#!/usr/bin/env python3
"""Canary pipeline: plan a run, apply assessed updates, validate, and build derived files.

  python scripts/canary.py prep [--full] [--force]
                                           # start of every run: pre-fill holds for measured signals whose data
                                           # hasn't moved, write work/brief.md (what needs judgement) and
                                           # work/updates.json; --full = no holds (automatic in the 05:40 run)
  python scripts/canary.py plan            # what is due this run + metric-based suggestions
  python scripts/canary.py apply FILE      # merge an updates JSON into status, then build + check
  python scripts/canary.py build           # rebuild derived files (catalogue, world index, feed, agent outputs, pages)
  python scripts/canary.py check           # validate everything; non-zero exit on any error
  python scripts/canary.py lock --reason "…" [--version X.Y] [--freeze-until YYYY-MM-DD] [--override-freeze]
                                           # record an owner-approved catalogue change (see CLAUDE.md)

Data files (all under site/data/):
  status.json    current state of every signal (written only via `apply`)
  history.json   per-signal status/value timeline
  changes.json   log of status changes (feeds the Atom feed and 'changed in 24h')
  runs.json      log of assessment runs
  world.json     World State index at each assessment, as [time, score] pairs (oldest first).
                 world_v1.json is the archived series from the first index method (to 2 Nov 2026).
  metrics.json   hard numbers from scripts/fetch_metrics.py
  catalogue.json generated from signals/catalogue.yaml for the site

Derived public outputs (now.md, status.md, s/*, api/v1/*, llms.txt, feed.xml, …) are
written by scripts/publish.py during `build`.
"""
from __future__ import annotations

import hashlib
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
# Holds (approved by Dan, 3 Nov 2026): a run may keep a signal's last written assessment (text and sources)
# and refresh only its numbers, for at most HOLD_MAX_H since that text was written (`assessed_at`).
# `prep` proposes measured holds only while the text is under PREP_HOLD_MAX_H old, so the next run is
# still inside the limit, and never in the full-sweep run (UK hour 5, the 05:40 run).
HOLD_MAX_H, PREP_HOLD_MAX_H, FULL_SWEEP_UK_HOURS = 24, 18, {5, 6}
HOLD_KEYS = {"id", "hold", "value", "value_num", "rubric_hit"}  # all a hold entry may carry
WORK = ROOT / "work"
HISTORY_CAP, CHANGES_CAP, RUNS_CAP = 240, 400, 200
WORLD_CAP = 720  # about six months at four runs a day
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
COVERAGE = ROOT / "signals" / "coverage.yaml"
LOCK = ROOT / "signals" / "catalogue.lock.json"
CHANGELOG = ROOT / "signals" / "CHANGELOG.md"

# How a status was set (shown on every signal; see "How each status is set" in methodology):
#   measured  — a fixed rule in this file applied to data fetched from open feeds (reproducible)
#   published — follows a figure or classification by the body named in the catalogue's `published`
#   judged    — the AI assessor's reading of sources against the rubric
BASES = ("measured", "published", "judged")
DECLARABLE_BASES = {"published", "judged"}  # "measured" is computed, never declared

# Sourcing rules (see trusted_sources.yaml)
ALERT_MIN_OUTLETS = 2          # a judged Alert needs this many independent outlets…
OUTLET_WARN, OUTLET_MAX = 0.10, 0.20  # …and no news outlet may supply more than OUTLET_MAX of a run
OUTLET_MIN_CITATIONS = 20      # the concentration check applies once a run has this many news citations
SECOND_LEVEL = {               # public suffixes with two labels, for telling outlets apart
    "co.uk", "org.uk", "ac.uk", "gov.uk", "nhs.uk", "ltd.uk", "plc.uk", "me.uk", "com.au", "net.au", "org.au",
    "gov.au", "edu.au", "co.nz", "govt.nz", "co.jp", "go.jp", "or.jp", "ne.jp", "co.kr", "or.kr", "go.kr",
    "com.cn", "gov.cn", "com.hk", "gov.hk", "com.sg", "gov.sg", "com.tw", "gov.tw", "co.in", "gov.in", "org.in",
    "com.pk", "gov.pk", "co.za", "gov.za", "com.tr", "gov.tr", "com.br", "gov.br", "com.mx", "gob.mx",
    "com.ar", "gob.ar", "co.il", "gov.il", "com.eg", "gov.eg", "com.ng", "gov.ng", "co.ke", "go.ke",
    "com.ua", "gov.ua", "com.ru", "com.sa", "gov.sa", "co.th", "go.th", "com.my", "gov.my", "com.ph", "gov.ph",
    "co.id", "go.id", "com.vn", "gov.vn", "com.qa", "gov.qa", "co.ae", "gov.ae",
}

# World State index method. Version 2 (from 2 Nov 2026): equal domain weights, and signals that
# share a situation count once within each domain. world_v1.json keeps the version 1 series.
INDEX_METHOD = 2

# Catalogue governance
LOCK_KEYS = ("id", "domain", "tier", "horizon", "metrics", "rubric", "published")
EMERGING_PROMOTE_DAYS = 14   # an emerging risk carried this long is a promotion candidate
RETIRE_REVIEW_DAYS = 90      # a signal Normal at every check for this long is a review candidate


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


# ───────────────────────── sources and basis ─────────────────────────

def host_of(url: str) -> str:
    try:
        host = url.split("/")[2].split(":")[0].lower()
    except IndexError:
        return ""
    return re.sub(r"^www\.", "", host)


def outlet(url_or_host: str) -> str:
    """Registrable domain, so that news.example.com and example.com count as one outlet."""
    host = host_of(url_or_host) if "//" in url_or_host else url_or_host.lower()
    parts = host.split(".")
    if len(parts) >= 3 and ".".join(parts[-2:]) in SECOND_LEVEL:
        return ".".join(parts[-3:])
    return ".".join(parts[-2:])


def under(host: str, suffixes) -> bool:
    return any(host == d or host.endswith("." + d) for d in suffixes)


_LISTS: dict | None = None


def source_lists() -> dict:
    """trusted / avoid / official domain suffixes from signals/trusted_sources.yaml."""
    global _LISTS
    if _LISTS is None:
        raw = (yaml.safe_load(TRUSTED.read_text()) or {}) if TRUSTED.exists() else {}
        _LISTS = {k: {d.lower().strip() for d in raw.get(k) or []} for k in ("domains", "avoid", "official")}
    return _LISTS


def published_source(sig: dict, sources: list) -> bool:
    doms = (sig.get("published") or {}).get("domains") or []
    return bool(doms) and any(under(host_of(x.get("url", "")), doms) for x in sources)


def decide_basis(sig: dict, requested: int, final: int, sug: dict | None, declared: str | None,
                 sources: list, override: str | None) -> tuple[str, str]:
    """How the final status was set. Returns (basis, detail)."""
    if sug and LEVEL[sug["status"]] == final and requested <= final:
        return "measured", sug["basis"]
    if declared == "published" and published_source(sig, sources):
        return "published", sig["published"]["by"]
    if sug and final < LEVEL[sug["status"]]:
        return "judged", "set below the data floor by assessor override"
    if sug and final > LEVEL[sug["status"]]:
        return "judged", "raised above the data floor on reported events"
    return "judged", ""


def infer_basis(sig: dict, cur: dict, metrics: dict) -> tuple[str, str]:
    """Best reconstruction for a status assessed before basis was recorded (used only by build)."""
    lvl = LEVEL.get(cur.get("status"))
    if lvl is None:
        return "judged", ""
    sug = suggest(sig["id"], metrics, lvl)
    if sug and LEVEL[sug["status"]] == lvl:
        return "measured", sug["basis"]
    if published_source(sig, cur.get("sources") or []):
        return "published", sig["published"]["by"]
    return "judged", ""


def news_concentration(sources: list) -> tuple[int, list[tuple[str, int]]]:
    """Citations by news outlet in one run, leaving out official bodies and data feeds."""
    official = source_lists()["official"]
    counts: dict[str, int] = {}
    for x in sources:
        h = host_of(x.get("url", ""))
        if h and not under(h, official):
            counts[outlet(h)] = counts.get(outlet(h), 0) + 1
    return sum(counts.values()), sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))


# ───────────────────────── catalogue governance ─────────────────────────

def _h(obj) -> str:
    return hashlib.sha256(json.dumps(obj, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:12]


def fingerprint(cat: dict) -> dict:
    """Hashes of everything that changes what Canary measures (not copy such as why/drivers/hints)."""
    sigs = {s["id"]: _h({k: s.get(k) for k in LOCK_KEYS}) for s in cat["signals"]}
    doms = _h([{k: d.get(k) for k in ("id", "weight")} for d in cat["domains"]])
    return {"catalogue": _h({"domains": doms, "signals": sigs}), "domains": doms, "signals": sigs}


def lock_diff(lock: dict, fp: dict) -> list[str]:
    old = lock.get("signals") or {}
    new = fp["signals"]
    out = [f"added {i}" for i in new if i not in old] + [f"removed {i}" for i in old if i not in new]
    out += [f"changed {i}" for i in new if i in old and old[i] != new[i]]
    if lock.get("domains") != fp["domains"]:
        out.append("domains or weights changed")
    return out


def load_lock() -> dict:
    return json.loads(LOCK.read_text()) if LOCK.exists() else {}


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

    levels, basis, parts = [], [], []
    for label, v, a, r in rules:
        raw = lv = _level(v, a, r)
        if lv is None:
            continue
        if prev_level is not None and lv < prev_level:
            lv = min(prev_level, max(lv, _level(v, a, r, MARGIN)))
        levels.append(lv)
        basis.append(f"{label}={v:.2f}" if isinstance(v, (int, float)) else f"{label}={v}")
        parts.append((lv, raw, label, v, a, r))
    for lv, why in triggers:
        levels.append(lv)
        basis.append(why)
    if not levels:
        return None
    top = max(levels)
    return {"status": NAME[top], "value": value, "value_num": num, "basis": "; ".join(basis),
            "hit": _rubric_hit(top, parts, triggers)}


_UNITS = ((" %", "{}%"), (" bp", "{}bp"), (" $bn", "${}bn"), (" $", "${}"), (" €/MWh", "€{}/MWh"), (" ppm", "{} ppm"))


def _split_unit(label: str) -> tuple[str, str]:
    for unit, tpl in _UNITS:
        if label.endswith(unit):
            return label[:-len(unit)], tpl
    return label, "{}"


def _num(v: float) -> str:
    s = f"{v:.0f}" if abs(v) >= 100 else f"{v:.1f}" if abs(v) >= 10 else f"{v:.2f}"
    return s.rstrip("0").rstrip(".") if "." in s else s


def _fmt_rule(label: str, v, thr: float | None = None) -> tuple[str, str]:
    """('Brent $', 113.4, 110) → ('Brent $113', '$110'); ('S&P drawdown %', 3.16, 5) → ('S&P drawdown 3.16%', '5%')."""
    name, tpl = _split_unit(label)
    shown = f"{name} {tpl.format(_num(v))}" if isinstance(v, (int, float)) else f"{name} {v}"
    return shown, (tpl.format(_num(thr)) if thr is not None else "")


def _rubric_hit(top: int, parts: list, triggers: list) -> str:
    """One line naming the rule that set the metric floor, for `rubric_hit` on held statuses (≤ 200 chars)."""
    word = {1: "Watch", 2: "Alert"}
    bits = []
    if top == 0:
        for _, _, lb, v, a, _ in parts:
            shown, t_ = _fmt_rule(lb, v, a)
            bits.append(f"{shown} below the {t_} Watch line")
        bits += [why for lv, why in triggers]
    else:
        for lv, raw, lb, v, a, r in parts:
            if lv != top:
                continue
            thr = r if top == 2 else a
            if raw is not None and raw < lv:  # held up by the hysteresis margin
                shown, t_ = _fmt_rule(lb, v, thr * (1 - MARGIN))
                bits.append(f"{shown} has not yet cleared the {t_} exit line, so {word[top]} holds")
            else:
                shown, t_ = _fmt_rule(lb, v, thr)
                bits.append(f"{shown} {'>' if top == 2 else '≥'} {t_} {word[top]} line")
        bits += [f"{why} ({word[top]})" for lv, why in triggers if lv == top]
    out = "; ".join(bits) or "Data within normal range"
    return out if len(out) <= LIMITS["rubric_hit"] else out[:LIMITS["rubric_hit"] - 1].rstrip("; ,") + "…"


# ───────────────────────── plan ─────────────────────────

def due(sig: dict, cur: dict | None, t: datetime) -> bool:
    if sig["tier"] == "fast" or not cur:
        return True
    last = parse(cur.get("checked_at"))
    return last is None or (t - last) > timedelta(hours=DAILY_DUE_H)


def governance_notes(cat: dict, status: dict, history: dict, t: datetime) -> str:
    """Catalogue version and freeze, plus candidates for the owner's weekly review (never acted on in a run)."""
    lock = load_lock()
    frozen = lock.get("frozen_until")
    lines = [f"catalogue v{lock.get('version', '?')}"
             + (f", frozen until {frozen} — do not add, remove or re-rubric signals" if frozen and frozen >= iso(t)[:10] else "")]
    promote = []
    for x in status.get("emerging") or []:
        first = parse((x.get("first_seen") or "") + "T00:00:00Z")
        if first and t - first >= timedelta(days=EMERGING_PROMOTE_DAYS):
            promote.append(f"{x['name']} (since {x['first_seen']})")
    if promote:
        lines.append(f"owner review — emerging risks carried {EMERGING_PROMOTE_DAYS}+ days: " + "; ".join(promote))
    quiet = []
    for s in cat["signals"]:
        h = history.get(s["id"]) or []
        first = parse(h[0][0]) if h else None
        if first and t - first >= timedelta(days=RETIRE_REVIEW_DAYS):
            recent = [p for p in h if (parse(p[0]) or t) >= t - timedelta(days=RETIRE_REVIEW_DAYS)]
            if recent and all(p[1] == "g" for p in recent):
                quiet.append(s["id"])
    if quiet:
        lines.append(f"owner review — Normal at every check for {RETIRE_REVIEW_DAYS} days: " + ", ".join(quiet))
    return "governance: " + "\n  ".join(lines)


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
    print(governance_notes(cat, status, load("history.json", {}), t))
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
        else:  # saves opening catalogue.yaml for the rubric
            line += "\n    " + rubric_line(s)
        print(line)
    if carry:
        print("\n## carried forward\n" + ", ".join(s["id"] for s in carry))
    return 0


def rubric_line(s: dict) -> str:
    r = s["rubric"]
    return f"rubric — Normal: {r['green']} | Watch: {r['amber']} | Alert: {r['red']}"


def uk_time(t: datetime) -> datetime:
    from zoneinfo import ZoneInfo
    return t.astimezone(ZoneInfo("Europe/London"))


def _hours(td: timedelta) -> str:
    return f"{td.total_seconds() / 3600:.0f}h"


# ───────────────────────── prep ─────────────────────────
# Runs first in every scheduled run (after fetch_metrics). It decides what needs Claude's judgement,
# pre-fills holds for measured signals whose data hasn't moved, and writes a short brief so the run
# never has to open catalogue.yaml or status.json. Approved by Dan on 3 Nov 2026.

TRIAGE_FILE = "triage.json"  # in work/: this run's shadow triage predictions, never shown to the assessor


def triage_quiet(cur: dict, hist: list, t: datetime) -> bool:
    """Shadow triage, method persistence-v0: would this judged/published signal have been skipped as quiet?
    Quiet = status unchanged for 72h and at its last four checks. A baseline to measure the hold rule
    against before any triage is switched on (news-activity scoring is the planned v1)."""
    ch = parse(cur.get("changed_at"))
    last = [p[1] for p in hist[-4:]]
    return bool(ch and t - ch >= timedelta(hours=72) and len(last) == 4 and len(set(last)) == 1)


def shadow_triage_outcome(t: datetime, changed: list, moved_trend: list) -> dict | None:
    """Compare this run's shadow predictions (written by prep) with what the assessor actually changed."""
    f = WORK / TRIAGE_FILE
    if not f.exists():
        return None
    try:
        tri = json.loads(f.read_text())
    except json.JSONDecodeError:
        return None
    made = parse(tri.get("t"))
    if not made or t - made > timedelta(hours=3):  # stale file from another run
        return None
    quiet = set(tri.get("quiet") or [])
    return {"method": tri.get("method"), "predicted_quiet": len(quiet), "predicted_active": len(tri.get("active") or []),
            "quiet_but_status_changed": sorted(quiet & set(changed)),
            "quiet_but_trend_changed": sorted(quiet & set(moved_trend))}


def cmd_prep(args) -> int:
    cat, status = catalogue(), load("status.json", {})
    mdoc = load("metrics.json", {})
    metrics, sigs, t = mdoc.get("metrics", {}), status.get("signals", {}), now()
    history = load("history.json", {})
    ukt = uk_time(t)
    full = "--full" in args or ukt.hour in FULL_SWEEP_UK_HOURS
    avoid = source_lists()["avoid"]
    mfetch = parse(mdoc.get("fetched_at"))
    todo, carry = [], []
    for s in cat["signals"]:
        (todo if due(s, sigs.get(s["id"]), t) else carry).append(s)

    holds, review, quiet, active = [], [], [], []
    for s in todo:
        cur = sigs.get(s["id"]) or {}
        lvl = LEVEL.get(cur.get("status"))
        sug = suggest(s["id"], metrics, lvl)
        w = written_at(cur) if cur else None
        why = None
        if not cur:
            why = "never assessed: give it a full first assessment"
        elif sug:
            flo = LEVEL[sug["status"]]
            if flo > lvl:
                why = f"metric floor rose to {LABEL[sug['status']].upper()} (from {LABEL[cur['status']]})"
            elif flo < lvl and cur.get("basis") == "measured":
                why = f"data now rates it {LABEL[sug['status']].upper()}, below its measured {LABEL[cur['status']]}"
            elif flo < lvl:
                why = (f"held above its {LABEL[sug['status']]} data floor on reported events: check those events "
                       "still justify it")
            elif full:
                why = "full sweep: refresh the text"
            elif not w or t - w > timedelta(hours=PREP_HOLD_MAX_H):
                why = f"text is {_hours(t - w) if w else '?'} old: refresh it"
            else:
                issue = source_issue(cur, avoid)
                if issue:
                    why = f"it {issue}: reassess with new sources"
        if sug and not why:
            h = {"id": s["id"], "hold": True}
            for k, src in (("value", "value"), ("value_num", "value_num"), ("rubric_hit", "hit")):
                if sug.get(src) not in (None, ""):
                    h[k] = sug[src]
            holds.append(h)
            continue
        if not sug and cur:
            (quiet if triage_quiet(cur, history.get(s["id"]) or [], t) else active).append(s["id"])
        review.append((s, cur, sug, why, w))

    # work/updates.json: holds + the previous situations to edit. Never overwrite the assessor's work.
    WORK.mkdir(exist_ok=True)
    upath = WORK / "updates.json"
    wrote_updates = False
    if "--force" in args or not upath.exists():
        upath.write_text(json.dumps({"run": {"headline": "", "situations": status.get("situations") or []},
                                     "signals": holds}, indent=1, ensure_ascii=False) + "\n")
        wrote_updates = True
    (WORK / TRIAGE_FILE).write_text(json.dumps({"t": iso(t), "method": "persistence-v0",
                                                "quiet": quiet, "active": active}) + "\n")

    def uk(ts: datetime | None) -> str:
        return uk_time(ts).strftime("%-d %b %H:%M") if ts else "—"

    L = [f"# Canary run brief — {iso(t)} ({ukt.strftime('%-d %b %H:%M')} UK)",
         ("**Mode: FULL SWEEP.** The 05:40 run rewrites every due signal's text; prep proposes no holds."
          if full else "Mode: normal run."),
         f"Metrics fetched {uk(mfetch)} UK" + (" ⚠ older than 3h: run scripts/fetch_metrics.py, then prep --force"
                                              if not mfetch or t - mfetch > timedelta(hours=3) else "") + ".",
         f"Due {len(todo)} · held by prep {len(holds)} (measured, data unchanged) · **for you to assess "
         f"{len(review)}** · carried forward {len(carry)} (daily, fresh).", ""]
    anchors = []
    for key, label in (("gpr", "Geopolitical Risk index (7d avg)"), ("epu", "US policy uncertainty (7d avg)"),
                       ("ciss", "ECB systemic stress"), ("gas_storage", "EU gas storage % full")):
        m = metrics.get(key) or {}
        if m.get("value") is not None:
            rel = f", {m['vs_1y_median']}× its 1-year median" if m.get("vs_1y_median") else ""
            anchors.append(f"- {label}: {m['value']}{rel} (as of {m.get('as_of')})")
    if anchors:
        L += ["Context anchors (inform judgement; never set a status):"] + anchors + [""]
    L += [governance_notes(cat, status, history, t), ""]
    L += ["## Already in work/updates.json",
          f"- **{len(holds)} holds** for measured signals whose data leaves their status unchanged (listed at the end). "
          "`apply` refreshes their numbers and keeps the last text and sources. Replace a hold with a full update "
          "only if you find an event that should raise the status.",
          "- **run.situations**: the previous list. Edit it rather than rebuilding it.",
          "- Still to write: **run.headline** (required, ≤ 260 chars) and **run.emerging** after the surprise check "
          "(omit the key to keep the previous list; previous items below)."
          + ("" if wrote_updates else "\n- ⚠ work/updates.json already existed, so prep left it alone "
                                      "(run `prep --force` to rebuild it)."), ""]
    L += ["## To assess",
          f"Write a full update for each signal below, unless the signal says a hold is allowed and your search "
          f"finds nothing new since its text was written: then send `{{\"id\": \"…\", \"hold\": true}}` "
          f"(optionally with a fresh value/value_num). A hold keeps the last text and sources for at most "
          f"{HOLD_MAX_H}h after they were written.", ""]
    dom = None
    for s, cur, sug, why, w in review:
        if s["domain"] != dom:
            dom = s["domain"]
            L.append(f"### {dom}")
        if cur:
            head = (f"- **{s['id']}** · {s['name']} · {s['tier']} · now {LABEL[cur['status']].upper()} "
                    f"({cur.get('trend', '?')}) · {cur.get('basis', 'judged')} · text written {uk(w)} UK")
        else:
            head = f"- **{s['id']}** · {s['name']} · {s['tier']} · not yet assessed"
        L.append(head)
        if why:
            L.append(f"  - flagged: {why}")
        if sug:
            L.append(f"  - data floor: {LABEL[sug['status']].upper()} · {sug['value'] or '—'} · {sug['basis']}")
        L.append("  - " + rubric_line(s))
        if s.get("published"):
            p = s["published"]
            L.append(f"  - published body: {p['by']} ({', '.join(p['domains'])})")
        if s.get("hints"):
            L.append("  - hints: " + "; ".join(s["hints"]))
        if cur:
            L.append(f"  - value: {cur.get('value') or '—'} · summary: {cur.get('summary') or '—'}")
            L.append(f"  - previous state: {cur.get('state') or '—'}")
            if not sug:
                issue = source_issue(cur, avoid)
                fresh = bool(w and t - w <= timedelta(hours=HOLD_MAX_H - 2))  # 2h margin for the run itself
                if fresh and not issue and not full:
                    L.append(f"  - hold allowed: yes, if nothing new (text expires {uk(w + timedelta(hours=HOLD_MAX_H))} UK)")
                else:
                    L.append(f"  - hold allowed: no ({issue or ('full sweep' if full else 'text too old')})")
    L.append("")
    em = status.get("emerging") or []
    L += ["## Previous emerging risks"] + ([f"- {x['name']} ({x['status']}, first seen {x.get('first_seen', '?')}): "
                                             f"{x.get('summary', '')}" for x in em] or ["- none"]) + [""]
    L += ["## Held by prep (measured, data unchanged)"] + [
        f"- {h['id']}: {h.get('value', '—')} · {h.get('rubric_hit', '')}" for h in holds] + (["- none"] if not holds else [])
    if carry:
        L += ["", "## Carried forward (not due)", ", ".join(s["id"] for s in carry)]
    (WORK / "brief.md").write_text("\n".join(L) + "\n")
    print(f"prep: {len(todo)} due · {len(holds)} held · {len(review)} to assess · {len(carry)} carried"
          f"{' · FULL SWEEP' if full else ''}\nbrief → work/brief.md ({publish.est_tokens(chr(10).join(L))} tokens est.)"
          f"\nupdates → work/updates.json{'' if wrote_updates else ' (existing file kept; --force to rebuild)'}")
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
    metrics = load("metrics.json", {}).get("metrics", {})
    sigs = status.setdefault("signals", {})
    bad, src_warns = validate_updates(upd, by_id, metrics, sigs)
    if bad:  # reject before touching any data file, so a fixed file can simply be re-applied
        for e in bad:
            print("ERROR:", e)
        for w in src_warns:
            print("WARN", w)
        print(f"apply aborted: {len(bad)} problem(s) in {args[0]}; nothing was written")
        return 1
    history = load("history.json", {})
    changes = load("changes.json", [])
    runs = load("runs.json", [])
    t = now()
    warnings, applied, changed, held = list(src_warns), 0, [], []
    bases = {b: 0 for b in BASES}
    cited: list = []
    moved_trend: list[str] = []

    for u in upd.get("signals", []):
        sid = u.get("id")
        if sid not in by_id:
            warnings.append(f"unknown signal id '{sid}' — skipped")
            continue
        prev = sigs.get(sid) or {}
        prev_lvl = LEVEL.get(prev.get("status"))
        if u.get("hold"):  # keep the last full assessment's text and sources; refresh numbers only
            new = dict(prev)
            new.setdefault("assessed_at", prev.get("checked_at"))
            for k in ("value", "value_num", "rubric_hit"):
                if u.get(k) not in (None, ""):
                    new[k] = u[k]
            sug = suggest(sid, metrics, prev_lvl)
            if sug and LEVEL[sug["status"]] == prev_lvl:  # the data floor decides the status
                new["basis"], new["basis_detail"] = "measured", sug["basis"]
                if not u.get("value") and sug.get("value"):
                    new["value"] = sug["value"]
                if u.get("value_num") is None and sug.get("value_num") is not None:
                    new["value_num"] = sug["value_num"]
                if not u.get("rubric_hit") and sug.get("hit"):
                    new["rubric_hit"] = sug["hit"]
            new["checked_at"] = iso(t)
            bases[new.get("basis") if new.get("basis") in BASES else "judged"] += 1
            sigs[sid] = new
            h = history.setdefault(sid, [])
            h.append([iso(t), new["status"][0], new.get("value_num")])
            del h[:-HISTORY_CAP]
            held.append(sid)
            applied += 1
            continue
        if prev.get("trend") and u.get("trend") and u["trend"] != prev["trend"]:
            moved_trend.append(sid)
        new = {**prev, **{k: v for k, v in u.items() if k not in ("id", "override_reason", "basis")}}
        lvl = LEVEL.get(new.get("status"))
        if lvl is None:
            warnings.append(f"{sid}: invalid status '{new.get('status')}' — skipped")
            continue
        requested = lvl
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
        new["basis"], new["basis_detail"] = decide_basis(by_id[sid], requested, lvl, sug, u.get("basis"),
                                                         new.get("sources") or [], override)
        bases[new["basis"]] += 1
        cited += u.get("sources") or []
        if sug and not u.get("value") and sug.get("value"):
            new["value"] = sug["value"]
        if sug and new.get("value_num") is None and sug.get("value_num") is not None:
            new["value_num"] = sug["value_num"]
        if override:
            new["override_reason"] = override
        else:
            new.pop("override_reason", None)
        new["checked_at"] = new["assessed_at"] = iso(t)
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
    status["world"] = world_index(cat, sigs, status.get("situations"))
    for x in status.get("emerging") or []:
        cited += x.get("sources") or []
    n_news, by_outlet = news_concentration(cited)
    entry = {"t": iso(t), "applied": applied, "changed": changed, "warnings": warnings,
             "note": run.get("note", ""), "catalogue": load_lock().get("version"),
             "basis": bases, "held": len(held),
             "sources": {"citations": len(cited), "news_citations": n_news,
                         "outlets": len({outlet(x.get('url', '')) for x in cited}),
                         "top_news_outlets": [list(kv) for kv in by_outlet[:5]]}}
    tri = shadow_triage_outcome(t, changed, moved_trend)
    if tri:
        entry["triage"] = tri
    runs.insert(0, entry)
    save("status.json", status)
    save("history.json", history)
    save("changes.json", changes[:CHANGES_CAP])
    save("runs.json", runs[:RUNS_CAP])
    for w in warnings:
        print("WARN", w)
    print(f"applied {applied} signal updates ({len(held)} held); {len(changed)} status changes: "
          f"{', '.join(changed) or '—'}")
    print("basis this run: " + ", ".join(f"{v} {k}" for k, v in bases.items())
          + (f"; top news outlet {by_outlet[0][0]} {by_outlet[0][1]}/{n_news}" if by_outlet else ""))
    cmd_build([])
    return cmd_check([])


# ───────────────────────── build ─────────────────────────

def world_index(cat: dict, sigs: dict, situations: list | None = None) -> dict:
    """World State index, method 2.

    Each signal scores 0/1/2 (Normal/Watch/Alert). Within a domain, signals that belong to the same
    situation count once, at the highest level among them, so one event cannot fill a domain on its
    own. A signal listed in several situations counts with the first. Domain means are then combined
    with the catalogue weights (all 1.0 since 2 Nov 2026).
    """
    group: dict[str, str] = {}
    for x in situations or []:
        for sid in x.get("signals") or []:
            group.setdefault(sid, x.get("id") or "?")
    num = den = 0.0
    counts = {"green": 0, "amber": 0, "red": 0}
    by_dom = {}
    for d in cat["domains"]:
        units: dict[str, int] = {}
        for s in cat["signals"]:
            st = sigs.get(s["id"], {}).get("status")
            if s["domain"] != d["id"] or st not in LEVEL:
                continue
            key = f"situation:{group[s['id']]}" if s["id"] in group else s["id"]
            units[key] = max(units.get(key, 0), LEVEL[st])
        if not units:
            continue
        mean = sum(units.values()) / len(units)
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
    return {"score": score, "band": band, "status": colour, "counts": counts, "by_domain": by_dom,
            "method": INDEX_METHOD}


def world_series(cat: dict, status: dict, history: dict, series: list) -> list:
    """The World State index over time: one [time, score] point per assessment, oldest first.

    Append-only: a new assessment adds a point, and a rebuild with no new assessment (for example
    a catalogue edit) refreshes the latest point. Past points are never recomputed: situations are
    not kept per run, so method 2 cannot be replayed. The method 1 series is archived in
    world_v1.json.
    """
    series = [p for p in series if isinstance(p, list) and len(p) == 2]
    t, score = status.get("generated_at"), (status.get("world") or {}).get("score")
    if t and score is not None:
        if series and series[-1][0] == t:
            series[-1] = [t, score]
        elif not series or series[-1][0] < t:
            series.append([t, score])
    return series[-WORLD_CAP:]


def sentiment_config() -> dict | None:
    """signals/sentiment.yaml (issues and areas for the measured sentiment track), if present."""
    p = ROOT / "signals" / "sentiment.yaml"
    return yaml.safe_load(p.read_text()) if p.exists() else None


def coverage_config() -> dict | None:
    return yaml.safe_load(COVERAGE.read_text()) if COVERAGE.exists() else None


def cmd_build(_args) -> int:
    cat = catalogue()
    save("catalogue.json", cat)
    status = load("status.json", {"signals": {}})
    metrics = load("metrics.json", {}).get("metrics", {})
    by_id = {s["id"]: s for s in cat["signals"]}
    for sid, cur in status.get("signals", {}).items():
        # Statuses assessed before basis was recorded get a reconstructed one until their next check.
        if sid in by_id and cur.get("basis") not in BASES:
            cur["basis"], cur["basis_detail"] = infer_basis(by_id[sid], cur, metrics)
    status["world"] = world_index(cat, status.get("signals", {}), status.get("situations"))
    save("status.json", status)
    history = load("history.json", {})
    world = world_series(cat, status, history, load("world.json", []))
    save("world.json", world)
    written = publish.build(SITE_URL, cat, status, load("changes.json", []), history, metrics,
                            {"fast": FAST_STALE_H, "daily": DAILY_STALE_H}, world=world,
                            sentiment=load("sentiment.json", {}), sentiment_cfg=sentiment_config(),
                            coverage=coverage_config(), lock=load_lock())
    print(f"built catalogue.json, world index and public outputs ({len(written)} files changed)")
    return 0


# ───────────────────────── check ─────────────────────────

def alert_sourcing(where: str, sources: list, errs: list) -> None:
    """A judged Alert needs independent corroboration from at least one established outlet."""
    trusted = source_lists()["domains"]
    outlets = {outlet(x.get("url", "")) for x in sources if host_of(x.get("url", ""))}
    if len(outlets) < ALERT_MIN_OUTLETS or not any(under(host_of(x.get("url", "")), trusted) for x in sources):
        errs.append(f"{where}: a judged Alert needs sources from at least {ALERT_MIN_OUTLETS} different outlets, "
                    f"one on signals/trusted_sources.yaml (has {len(outlets)}: {', '.join(sorted(outlets)) or '—'}). "
                    "Find corroboration, or rate Watch and say in state that the Alert is unconfirmed")


def validate_updates(upd: dict, by_id: dict, metrics: dict | None = None,
                     sigs: dict | None = None) -> tuple[list[str], list[str]]:
    """Structural, safety and sourcing checks on an updates file, run before anything is merged.

    Returns (errors, warnings). Any error aborts the apply.
    """
    errs: list[str] = []
    warns: list[str] = []
    metrics, sigs = metrics or {}, sigs or {}
    avoid = source_lists()["avoid"]
    cited: list = []
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
        check_sources(f"emerging '{nm}'", x.get("sources") or [], set(), errs, {}, avoid=avoid)
        if x.get("status") == "red":
            alert_sourcing(f"emerging '{nm}'", x.get("sources") or [], errs)
        cited += x.get("sources") or []
    if len(run.get("emerging") or []) > MAX_EMERGING:
        errs.append(f"run.emerging: max {MAX_EMERGING}")
    for u in upd.get("signals", []):
        sid = u.get("id", "?")
        if sid not in by_id:
            continue
        if u.get("hold"):
            hold_problems(sid, u, sigs.get(sid), metrics, errs, avoid)
            continue
        sig, srcs = by_id[sid], u.get("sources") or []
        check_text(sid, {f: u.get(f) for f in PROSE}, errs)
        check_sources(sid, srcs, set(), errs, {}, avoid=avoid)
        cited += srcs
        declared = u.get("basis")
        if declared is not None and declared not in DECLARABLE_BASES:
            errs.append(f"{sid}: basis must be 'published' or 'judged' (measured is worked out by apply; omit it)")
        if declared == "published":
            if not sig.get("published"):
                errs.append(f"{sid}: basis 'published' is only for signals with a `published` body in the catalogue")
            elif not published_source(sig, srcs):
                errs.append(f"{sid}: basis 'published' needs a source from {', '.join(sig['published']['domains'])} "
                            f"({sig['published']['by']})")
        prev = sigs.get(sid) or {}
        st = u.get("status") or prev.get("status")
        if st == "red":
            sug = suggest(sid, metrics, LEVEL.get(prev.get("status")))
            measured = bool(sug and sug["status"] == "red")
            published = declared == "published" and published_source(sig, srcs)
            if not (measured or published):
                alert_sourcing(sid, srcs, errs)
    n_news, by_outlet = news_concentration(cited)
    if n_news >= OUTLET_MIN_CITATIONS:
        for dom, n in by_outlet:
            share = n / n_news
            if share > OUTLET_MAX:
                errs.append(f"sources: {dom} supplies {n} of {n_news} news citations ({share:.0%}, max "
                            f"{OUTLET_MAX:.0%}). Replace some with other outlets, ideally regional or non-English ones")
            elif share > OUTLET_WARN:
                warns.append(f"sources: {dom} supplies {n} of {n_news} news citations ({share:.0%}); "
                             f"diversify next run (errors above {OUTLET_MAX:.0%})")
    return errs, warns


def written_at(cur: dict) -> datetime | None:
    """When a status's text and sources were last written by a full assessment (before holds existed,
    every check was a full assessment, so checked_at stands in)."""
    return parse(cur.get("assessed_at") or cur.get("checked_at"))


def source_issue(cur: dict, avoid: set | None = None) -> str | None:
    """A reason the current sources can't be carried forward by a hold, or None."""
    avoid = source_lists()["avoid"] if avoid is None else avoid
    bad = sorted({host_of(x.get("url", "")) for x in cur.get("sources") or [] if under(host_of(x.get("url", "")), avoid)})
    if bad:
        return "cites avoid-list domain(s) " + ", ".join(bad)
    if cur.get("status") == "red" and cur.get("basis") == "judged":
        probe: list[str] = []
        alert_sourcing("-", cur.get("sources") or [], probe)
        if probe:
            return "judged Alert without two independent outlets"
    return None


def hold_problems(sid: str, u: dict, prev: dict | None, metrics: dict, errs: list, avoid: set,
                  t: datetime | None = None) -> None:
    """A hold keeps the last full assessment's text and sources and refreshes only numbers. Allowed only
    when that text is under HOLD_MAX_H old, the data doesn't call for a status change, and the carried
    sources still meet the sourcing rules."""
    t = t or now()
    extra = sorted(set(u) - HOLD_KEYS)
    if extra:
        errs.append(f"{sid}: a hold may carry only value, value_num and rubric_hit (has {', '.join(extra)}); "
                    "send a full update instead")
    if not prev or prev.get("status") not in LEVEL:
        errs.append(f"{sid}: cannot hold a signal that has never been assessed")
        return
    w = written_at(prev)
    if not w or t - w > timedelta(hours=HOLD_MAX_H):
        errs.append(f"{sid}: its text was last written {iso(w) if w else 'never'}, more than {HOLD_MAX_H}h ago; "
                    "a hold is not allowed, so send a full assessment with sources from this run")
    sug = suggest(sid, metrics, LEVEL[prev["status"]])
    if sug and LEVEL[sug["status"]] > LEVEL[prev["status"]]:
        errs.append(f"{sid}: the metric floor is now {sug['status']}, above {prev['status']}; send a full update")
    elif sug and prev.get("basis") == "measured" and LEVEL[sug["status"]] < LEVEL[prev["status"]]:
        errs.append(f"{sid}: the data now rates it {sug['status']}, below its measured {prev['status']}; "
                    "send a full update for the status change")
    why = source_issue(prev, avoid)
    if why:
        errs.append(f"{sid}: can't be held because it {why}; reassess it with new sources")
    check_text(sid, {f: u.get(f) for f in ("value", "rubric_hit")}, errs)


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


def check_sources(where: str, srcs: list, trusted: set, errs: list, untrusted: dict,
                  avoid: set | None = None, avoided: list | None = None) -> None:
    """Validate source entries. Avoid-list domains are errors when `avoid` is given (new assessments),
    or collected into `avoided` for a warning (published state)."""
    for src in srcs:
        url = src.get("url", "")
        if not re.match(r"https?://", url) or not src.get("title"):
            errs.append(f"{where}: bad source {src}")
            continue
        check_text(where, {"source title": src.get("title")}, errs, limit=200)
        host = host_of(url)
        if avoid and under(host, avoid):
            errs.append(f"{where}: {host} is not a source of record (avoid list in signals/trusted_sources.yaml); "
                        "cite the original reporting or the official body")
        if avoided is not None and under(host, source_lists()["avoid"]):
            avoided.append(f"{host} ({where})")
        if trusted and not under(host, trusted):
            untrusted.setdefault(host, set()).add(where)


def trusted_domains() -> set:
    return source_lists()["domains"]


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
        pub = s.get("published")
        if pub is not None and (not isinstance(pub, dict) or not pub.get("by") or not pub.get("domains")):
            errs.append(f"catalogue {s['id']}: published needs `by` and a non-empty `domains` list")
    # Governance: what Canary measures changes only through `canary.py lock` (owner-approved).
    lock = load_lock()
    if not lock:
        errs.append("signals/catalogue.lock.json missing: run `canary.py lock` (owner-approved changes only)")
    else:
        fp = fingerprint(cat)
        if fp["catalogue"] != lock.get("catalogue"):
            errs.append("catalogue changed without `canary.py lock` (" + "; ".join(lock_diff(lock, fp)[:12])
                        + "). Signals, rubrics, tiers and weights change only with the owner's sign-off: see "
                        "'Changing the catalogue' in CLAUDE.md")
    cov = coverage_config()
    if cov:
        for x in cov.get("risks") or []:
            r = x.get("risk") or "?"
            if x.get("coverage") not in ("covered", "partial", "gap"):
                errs.append(f"coverage '{r}': coverage must be covered|partial|gap")
            bad = [i for i in x.get("signals") or [] if i not in {s['id'] for s in cat['signals']}]
            if bad:
                errs.append(f"coverage '{r}': unknown signal ids {bad}")
            if x.get("coverage") != "covered" and not x.get("note"):
                errs.append(f"coverage '{r}': partial and gap entries need a note")
            if x.get("coverage") == "gap" and x.get("signals"):
                errs.append(f"coverage '{r}': a gap lists no signals")
            if len(x.get("note") or "") > 200:
                errs.append(f"coverage '{r}': note over 200 chars")
    status = load("status.json", {"signals": {}})
    sigs = status.get("signals", {})
    by_id = {s["id"]: s for s in cat["signals"]}
    avoided: list[str] = []
    weak_alerts: list[str] = []
    for sid, s in sigs.items():
        if sid not in by_id:
            errs.append(f"status: '{sid}' not in catalogue")
            continue
        if s.get("basis") not in BASES:
            warns.append(f"{sid}: no basis recorded (build reconstructs one; apply records it)")
        elif s.get("basis") == "judged" and s.get("status") == "red":
            probe: list[str] = []
            alert_sourcing(sid, s.get("sources") or [], probe)
            if probe:
                weak_alerts.append(sid)
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
        check_sources(sid, srcs, trusted, errs, untrusted, avoided=avoided)
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
        check_sources(f"emerging '{nm}'", x.get("sources") or [], trusted, errs, untrusted, avoided=avoided)
    if avoided:
        warns.append(f"{len(avoided)} citation(s) on the avoid list, carried from earlier runs (rejected in new "
                     "assessments; replace when next assessed): " + "; ".join(avoided))
    if weak_alerts:
        warns.append(f"{len(weak_alerts)} judged Alert(s) carried from earlier runs lack two independent outlets "
                     f"(one trusted): {', '.join(weak_alerts)}. The next assessment must meet the rule")
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


def cmd_lock(args) -> int:
    """Record an owner-approved catalogue change: new fingerprint, version and changelog entry.

    Only run this when Dan has approved the change. Never run it during a scheduled assessment.
    """
    opts, i = {}, 0
    while i < len(args):
        a = args[i]
        if a == "--override-freeze":
            opts["override"] = True
            i += 1
        elif a in ("--reason", "--version", "--freeze-until") and i + 1 < len(args):
            opts[a[2:]] = args[i + 1]
            i += 2
        else:
            print(f"unknown or incomplete option {a}", file=sys.stderr)
            return 2
    if not opts.get("reason"):
        print('usage: canary.py lock --reason "what changed and who approved it" [--version X.Y] '
              "[--freeze-until YYYY-MM-DD] [--override-freeze]", file=sys.stderr)
        return 2
    cat, lock, t = catalogue(), load_lock(), now()
    fp = fingerprint(cat)
    diff = lock_diff(lock, fp) if lock else ["first lock"]
    frozen = lock.get("frozen_until")
    if lock and diff and frozen and frozen >= iso(t)[:10] and not opts.get("override"):
        print(f"catalogue is frozen until {frozen}; changes: {'; '.join(diff)}. "
              "Pass --override-freeze only with the owner's explicit approval.", file=sys.stderr)
        return 1
    if "freeze-until" in opts and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", opts["freeze-until"]):
        print("--freeze-until must be YYYY-MM-DD", file=sys.stderr)
        return 2
    ver = opts.get("version")
    if not ver:
        major, _, minor = str(lock.get("version") or "1.0").partition(".")
        ver = f"{major}.{int(minor or 0) + 1}" if diff else str(lock.get("version"))
    new = {"version": ver, "locked_at": iso(t), "frozen_until": opts.get("freeze-until", frozen),
           "reason": opts["reason"], "signals_count": len(cat["signals"]), **fp}
    LOCK.write_text(json.dumps(new, indent=1, ensure_ascii=False) + "\n")
    head = "# Catalogue changelog\n\nEvery change to what Canary measures, newest first. Written by `canary.py lock`.\n"
    body = CHANGELOG.read_text().split("\n", 3)[3] if CHANGELOG.exists() and CHANGELOG.read_text().count("\n") >= 3 else ""
    entry = (f"\n## v{ver} — {iso(t)[:10]}\n\n{opts['reason']}\n\n"
             + (f"- Frozen until {new['frozen_until']}\n" if new.get("frozen_until") else "")
             + f"- {len(cat['signals'])} signals; changes: {', '.join(diff) or 'none'}\n")
    CHANGELOG.write_text(head + entry + body)
    print(f"locked catalogue v{ver} ({fp['catalogue']}); {', '.join(diff) or 'no changes'}")
    return 0


if __name__ == "__main__":
    cmds = {"plan": cmd_plan, "prep": cmd_prep, "apply": cmd_apply, "build": cmd_build, "check": cmd_check,
            "lock": cmd_lock}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print(__doc__)
        sys.exit(2)
    sys.exit(cmds[sys.argv[1]](sys.argv[2:]))
