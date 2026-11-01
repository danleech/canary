#!/usr/bin/env python3
"""Fetch hard numbers for Canary from open, no-key data sources.

Writes site/data/metrics.json. Each metric is fetched independently; a failure
keeps the previous value (flagged with "error") so one broken API never wipes data.

Licensing: site/data/ is public (and the repo is public), so metrics.json must not
republish third-party series we have no licence to redistribute. For RESTRICTED
sources (Yahoo Finance, ICE BofA indices, Cboe VIX on FRED, the academic EPU/GPR
indices) only the latest value and derived statistics are written, never the raw
daily series. US-government and agency data (FRED/BLS/EIA series, NOAA, NSIDC,
USGS, ECB, CISA, Environment Agency) keep a short series for sparklines.

Optional environment variables:
  AGSI_API_KEY   free key from agsi.gie.eu → EU gas storage (skipped if unset)

Usage: python scripts/fetch_metrics.py [metric ...]
"""
from __future__ import annotations

import csv
import io
import json
import os
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone, date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site" / "data" / "metrics.json"
UA = "Mozilla/5.0 (compatible; CanaryBot/1.1; +https://canary.danleech.com/methodology)"
RESTRICTED_FRED = {"BAMLH0A0HYM2", "VIXCLS"}  # ICE BofA and Cboe series carry redistribution limits
RESTRICTED_NOTE = "derived values only; raw series not republished (licence)"
NOW = datetime.now(timezone.utc)


def get(url: str, timeout: int = 25, headers: dict | None = None) -> bytes:
    last = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*", **(headers or {})})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"{url}: {last}")


def iso(ts: float | datetime | date | None) -> str | None:
    if ts is None:
        return None
    if isinstance(ts, str):
        return ts
    if isinstance(ts, (int, float)):
        ts = datetime.fromtimestamp(ts, timezone.utc)
    if isinstance(ts, datetime):
        return ts.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    return ts.isoformat()


def pct(a: float, b: float) -> float | None:
    return None if not b else round((a / b - 1) * 100, 2)


def series_stats(dates: list, vals: list) -> dict:
    """Common stats for a daily price series (oldest→newest)."""
    last = vals[-1]
    hi = max(vals[-252:])
    def back(n):
        return vals[-n - 1] if len(vals) > n else vals[0]
    week = vals[-6:]
    daily = [pct(week[i], week[i - 1]) for i in range(1, len(week))]
    return {
        "value": round(last, 4),
        "as_of": iso(dates[-1]),
        "high_52w": round(hi, 4),
        "drawdown_pct": round((last / hi - 1) * 100, 2),
        "chg_1w_pct": pct(last, back(5)),
        "chg_1m_pct": pct(last, back(21)),
        "chg_3m_pct": pct(last, back(63)),
        "chg_1m_abs": round(last - back(21), 4),
        "worst_day_5d_pct": min([d for d in daily if d is not None], default=None),
        "series": [round(v, 4) for v in vals[-90:]],
    }


# ─────────── sources ───────────

def yahoo(symbol: str) -> dict:
    url = f"https://query1.finance.yahoo.com/v8/finance/chart/{urllib.request.quote(symbol)}?range=1y&interval=1d"
    d = json.loads(get(url))["chart"]["result"][0]
    ts = d["timestamp"]
    closes = d["indicators"]["quote"][0]["close"]
    pairs = [(t, c) for t, c in zip(ts, closes) if c is not None]
    meta = d["meta"]
    # prefer the live regular-market price for the latest point
    if meta.get("regularMarketPrice") and meta.get("regularMarketTime"):
        if meta["regularMarketTime"] > pairs[-1][0]:
            pairs.append((meta["regularMarketTime"], meta["regularMarketPrice"]))
        else:
            pairs[-1] = (meta["regularMarketTime"], meta["regularMarketPrice"])
    s = series_stats([p[0] for p in pairs], [p[1] for p in pairs])
    s.pop("series")
    s.update(source="Yahoo Finance", url=f"https://finance.yahoo.com/quote/{urllib.request.quote(symbol)}",
             licence=RESTRICTED_NOTE)
    return s


def fred(series_id: str) -> tuple[list[str], list[float]]:
    raw = get(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}").decode()
    rows = list(csv.reader(io.StringIO(raw)))[1:]
    out = [(r[0], float(r[1])) for r in rows if len(r) > 1 and r[1] not in ("", ".")]
    return [o[0] for o in out], [o[1] for o in out]


def fred_metric(series_id: str, label: str) -> dict:
    d, v = fred(series_id)
    s = series_stats(d, v)
    s.update(source=f"FRED {series_id} ({label})", url=f"https://fred.stlouisfed.org/series/{series_id}")
    if series_id in RESTRICTED_FRED:
        s.pop("series")
        s["licence"] = RESTRICTED_NOTE
    return s


def with_fallback(primary, fallback):
    try:
        return primary()
    except Exception as e:  # noqa: BLE001
        print(f"  primary failed ({e}); trying fallback", file=sys.stderr)
        return fallback()


def cpi_yoy() -> dict:
    d, v = fred("CPIAUCSL")
    yoy = [round((v[i] / v[i - 12] - 1) * 100, 2) for i in range(12, len(v))]
    return {
        "value": yoy[-1], "as_of": d[-1], "prev": yoy[-2], "series": yoy[-36:],
        "rising_3m": yoy[-1] > yoy[-2] > yoy[-3] > yoy[-4],
        "source": "FRED CPIAUCSL (BLS CPI-U, y/y %)", "url": "https://fred.stlouisfed.org/series/CPIAUCSL",
    }


def simple_fred(series_id: str, label: str, keep: int = 36) -> dict:
    d, v = fred(series_id)
    return {"value": v[-1], "as_of": d[-1], "prev": v[-2], "series": v[-keep:],
            "source": f"FRED {series_id} ({label})", "url": f"https://fred.stlouisfed.org/series/{series_id}"}


PAGER_RANK = {None: 0, "green": 1, "yellow": 2, "orange": 3, "red": 4}


def quakes() -> dict:
    g = json.loads(get("https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_week.geojson"))
    feats = g["features"]
    events = []
    for f in feats:
        p = f["properties"]
        events.append({"mag": p["mag"], "place": p["place"], "time": iso(p["time"] / 1000),
                       "alert": p.get("alert"), "tsunami": bool(p.get("tsunami")), "url": p["url"]})
    events.sort(key=lambda e: (PAGER_RANK.get(e["alert"], 0), e["mag"] or 0), reverse=True)
    top = max(feats, key=lambda f: f["properties"]["mag"] or 0)["properties"] if feats else None
    max_alert = max((e["alert"] for e in events), key=lambda a: PAGER_RANK.get(a, 0), default=None)
    return {
        "value": top["mag"] if top else 0,
        "as_of": iso(NOW),
        "count_m45": len(feats),
        "count_m6": sum(1 for e in events if (e["mag"] or 0) >= 6),
        "count_m7": sum(1 for e in events if (e["mag"] or 0) >= 7),
        "max_pager": max_alert,
        "tsunami_flags": sum(1 for e in events if e["tsunami"]),
        "top": events[:5],
        "source": "USGS (M4.5+ past 7 days)",
        "url": "https://earthquake.usgs.gov/earthquakes/map/",
    }


def gdacs() -> dict:
    g = json.loads(get("https://www.gdacs.org/gdacsapi/api/events/geteventlist/EVENTS4APP"))
    types = {"TC": "cyclone", "FL": "flood", "WF": "wildfire", "EQ": "earthquake", "VO": "volcano", "DR": "drought"}
    summary = {v: {"red": 0, "orange": 0, "green": 0, "events": []} for v in types.values()}
    for f in g.get("features", []):
        p = f["properties"]
        t = types.get(p.get("eventtype"))
        if not t:
            continue
        lvl = (p.get("alertlevel") or "").lower()
        if p.get("iscurrent") in (False, "false"):
            continue
        if lvl in summary[t]:
            summary[t][lvl] += 1
        if lvl in ("orange", "red") or t == "cyclone":
            summary[t]["events"].append({
                "name": p.get("name") or p.get("eventname"), "alert": lvl, "country": p.get("country"),
                "from": p.get("fromdate"), "to": p.get("todate"),
                "url": (p.get("url") or {}).get("report") if isinstance(p.get("url"), dict) else None,
            })
    worst = max((lvl for s in summary.values() for lvl in ("red", "orange") if s[lvl]),
                key=lambda l: {"orange": 1, "red": 2}[l], default="green")
    return {"value": worst, "as_of": iso(NOW), "by_type": summary,
            "source": "GDACS (UN/EC Global Disaster Alert and Coordination System)", "url": "https://www.gdacs.org/"}


def swpc() -> dict:
    d = json.loads(get("https://services.swpc.noaa.gov/products/noaa-scales.json"))
    cur = d["0"]
    fc = [d[k] for k in ("1", "2", "3") if k in d]
    def lvl(x, k):
        try:
            return int(x[k]["Scale"] or 0)
        except (TypeError, ValueError, KeyError):
            return 0
    # "-1" = past 24h maximum where present
    past = d.get("-1", cur)
    return {
        "value": f"G{lvl(cur,'G')} S{lvl(cur,'S')} R{lvl(cur,'R')}",
        "as_of": f"{cur['DateStamp']}T{cur['TimeStamp']}Z",
        "G": lvl(cur, "G"), "S": lvl(cur, "S"), "R": lvl(cur, "R"),
        "G_24h": max(lvl(cur, "G"), lvl(past, "G")), "S_24h": max(lvl(cur, "S"), lvl(past, "S")),
        "R_24h": max(lvl(cur, "R"), lvl(past, "R")),
        "G_forecast_max": max([0] + [int(x["G"].get("Scale") or 0) for x in fc if x.get("G")]),
        "source": "NOAA Space Weather Prediction Center", "url": "https://www.swpc.noaa.gov/",
    }


def co2() -> dict:
    raw = get("https://gml.noaa.gov/webdata/ccgg/trends/co2/co2_weekly_mlo.txt").decode()
    rows = [l.split() for l in raw.splitlines() if l and not l.startswith("#")]
    rows = [r for r in rows if float(r[4]) > 0]
    last = rows[-1]
    ppm, yago = float(last[4]), float(last[6])
    series = [float(r[4]) for r in rows[-104:]]
    return {"value": ppm, "as_of": f"{last[0]}-{int(last[1]):02d}-{int(last[2]):02d}",
            "yoy_ppm": round(ppm - yago, 2) if yago > 0 else None, "series": series,
            "source": "NOAA GML Mauna Loa (weekly)", "url": "https://gml.noaa.gov/ccgg/trends/"}


def oni() -> dict:
    raw = get("https://www.cpc.ncep.noaa.gov/data/indices/oni.ascii.txt").decode()
    rows = [l.split() for l in raw.splitlines()[1:] if l.strip()]
    vals = [float(r[3]) for r in rows]
    last = rows[-1]
    phase = "El Niño" if vals[-1] >= 0.5 else "La Niña" if vals[-1] <= -0.5 else "Neutral"
    return {"value": vals[-1], "as_of": f"{last[1]} {last[0]}", "phase": phase, "series": vals[-36:],
            "source": "NOAA CPC Oceanic Niño Index", "url": "https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/ONI_v5.php"}


def _ice(pole: str) -> dict:
    p = "north" if pole == "N" else "south"
    raw = get(f"https://noaadata.apps.nsidc.org/NOAA/G02135/{p}/daily/data/{pole}_seaice_extent_daily_v4.0.csv").decode()
    rows = []
    for r in csv.reader(io.StringIO(raw)):
        try:
            rows.append((int(r[0]), int(r[1]), int(r[2]), float(r[3])))
        except (ValueError, IndexError):
            continue
    y, m, d, ext = rows[-1]
    same_day = [e for (yy, mm, dd, e) in rows if mm == m and dd == d]
    clim = [e for (yy, mm, dd, e) in rows if mm == m and dd == d and 1981 <= yy <= 2010]
    prior = [e for (yy, mm, dd, e) in rows if mm == m and dd == d and yy < y]
    mean = sum(clim) / len(clim) if clim else None
    return {"extent": ext, "as_of": f"{y}-{m:02d}-{d:02d}",
            "anomaly": round(ext - mean, 3) if mean else None,
            "record_low_for_date": bool(prior) and ext < min(prior),
            "rank_low": sorted(same_day).index(ext) + 1 if ext in same_day else None,
            "series": [r[3] for r in rows[-90:]]}


def sea_ice() -> dict:
    n, s = _ice("N"), _ice("S")
    return {"value": n["anomaly"], "as_of": n["as_of"], "arctic": n, "antarctic": s,
            "source": "NSIDC Sea Ice Index v4 (anomaly vs 1981–2010, million km²)",
            "url": "https://nsidc.org/arcticseaicenews/sea-ice-tools/"}


def global_temp() -> dict:
    data = json.loads(get("https://climatereanalyzer.org/clim/t2_daily/json/era5_world_t2_day.json"))
    years = {d["name"]: d["data"] for d in data if d.get("name", "").isdigit()}
    cy = str(max(int(y) for y in years))
    cur = years[cy]
    idx = max(i for i, v in enumerate(cur) if v is not None)
    def clim(i):
        vals = [years[str(y)][i] for y in range(1991, 2021) if str(y) in years and years[str(y)][i] is not None]
        return sum(vals) / len(vals)
    anoms = [round(cur[i] - clim(i), 3) for i in range(max(0, idx - 89), idx + 1) if cur[i] is not None]
    prior_max = max(years[y][idx] for y in years if y != cy and len(years[y]) > idx and years[y][idx] is not None)
    a = anoms[-1]
    day = date(int(cy), 1, 1).toordinal() + idx
    return {"value": round(a + 0.88, 2), "anomaly_1991_2020": a, "as_of": date.fromordinal(day).isoformat(),
            "abs_c": cur[idx], "record_for_date": cur[idx] > prior_max,
            "series": [round(x + 0.88, 3) for x in anoms],
            "source": "Climate Reanalyzer (ERA5) — °C above pre-industrial ≈ 1991–2020 anomaly + 0.88",
            "url": "https://climatereanalyzer.org/clim/t2_daily/"}


def metoffice() -> dict:
    raw = get("https://www.metoffice.gov.uk/public/data/PWSCache/WarningsRSS/Region/UK")
    root = ET.fromstring(raw)
    items = []
    for it in root.iter("item"):
        title = (it.findtext("title") or "").strip()
        m = re.match(r"(Yellow|Amber|Red)", title, re.I)
        items.append({"title": title, "level": m.group(1).lower() if m else None, "link": it.findtext("link")})
    counts = {k: sum(1 for i in items if i["level"] == k) for k in ("yellow", "amber", "red")}
    worst = "red" if counts["red"] else "amber" if counts["amber"] else "yellow" if counts["yellow"] else "none"
    return {"value": worst, "as_of": iso(NOW), "counts": counts, "items": items[:12],
            "source": "Met Office National Severe Weather Warnings",
            "url": "https://www.metoffice.gov.uk/weather/warnings-and-advice/uk-warnings"}


# ─────────── quantitative anchors added Nov 2026 ───────────

def _on_or_before(dates: list[str], vals: list[float], day: str) -> float | None:
    best = None
    for d, v in zip(dates, vals):
        if d <= day:
            best = v
    return best


def sofr_iorb() -> dict:
    """Overnight funding stress: SOFR minus the Fed's interest on reserve balances, in bp."""
    sd, sv = fred("SOFR")
    idates, ivals = fred("IORB")
    spreads = []
    for d, v in list(zip(sd, sv))[-90:]:
        i = _on_or_before(idates, ivals, d)
        if i is not None:
            spreads.append((d, round((v - i) * 100, 1)))
    if not spreads:
        raise RuntimeError("no overlapping SOFR/IORB dates")
    last5 = [s for _, s in spreads[-5:]]
    return {"value": spreads[-1][1], "as_of": spreads[-1][0], "max_5d_bp": max(last5),
            "sofr": sv[-1], "iorb": _on_or_before(idates, ivals, sd[-1]),
            "series": [s for _, s in spreads],
            "source": "FRED SOFR minus IORB (New York Fed / Federal Reserve)",
            "url": "https://fred.stlouisfed.org/series/SOFR"}


def repo_ops() -> dict:
    """Fed overnight repo operations (Standing Repo Facility take-up), $bn."""
    d, v = fred("RPONTSYD")
    return {"value": round(v[-1], 3), "as_of": d[-1], "max_5d": round(max(v[-5:]), 3), "series": v[-90:],
            "source": "FRED RPONTSYD (Fed overnight repo operations, $bn)",
            "url": "https://fred.stlouisfed.org/series/RPONTSYD"}


def icsa() -> dict:
    """US initial jobless claims: 4-week average versus its 52-week low."""
    d, v = fred("ICSA")
    avg4 = [sum(v[i - 3:i + 1]) / 4 for i in range(3, len(v))]
    low = min(avg4[-52:])
    return {"value": v[-1], "as_of": d[-1], "avg4": round(avg4[-1]), "low52_avg4": round(low),
            "above_low_pct": round((avg4[-1] / low - 1) * 100, 1), "series": v[-52:],
            "source": "FRED ICSA (US Department of Labor initial claims)",
            "url": "https://fred.stlouisfed.org/series/ICSA"}


def usdjpy() -> dict:
    return with_fallback(lambda: yahoo("JPY=X"), lambda: fred_metric("DEXJPUS", "USD/JPY"))


def kev() -> dict:
    """CISA Known Exploited Vulnerabilities: additions in the past 7 and 30 days."""
    k = json.loads(get("https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"))
    vs = k.get("vulnerabilities", [])
    today = NOW.date()
    def age(x):
        return (today - date.fromisoformat(x["dateAdded"])).days
    recent = sorted((x for x in vs if age(x) < 30), key=lambda x: x["dateAdded"], reverse=True)
    week = [x for x in recent if age(x) < 7]
    return {"value": len(week), "as_of": k.get("dateReleased", iso(NOW))[:10], "count_7d": len(week),
            "count_30d": len(recent),
            "ransomware_30d": sum(1 for x in recent if x.get("knownRansomwareCampaignUse") == "Known"),
            "latest": [{"cve": x["cveID"], "vendor": x["vendorProject"], "product": x["product"],
                        "added": x["dateAdded"]} for x in recent[:6]],
            "source": "CISA Known Exploited Vulnerabilities catalogue",
            "url": "https://www.cisa.gov/known-exploited-vulnerabilities-catalog"}


def ea_floods() -> dict:
    """Environment Agency (England) flood warnings currently in force."""
    d = json.loads(get("https://environment.data.gov.uk/flood-monitoring/id/floods"))
    items = d.get("items", [])
    counts = {"severe": 0, "warning": 0, "alert": 0}
    for it in items:
        k = {1: "severe", 2: "warning", 3: "alert"}.get(it.get("severityLevel"))
        if k:
            counts[k] += 1
    worst = [{"area": it.get("description"), "level": it.get("severity")}
             for it in sorted(items, key=lambda x: x.get("severityLevel") or 9)[:5]
             if it.get("severityLevel") in (1, 2)]
    return {"value": counts["warning"], "as_of": iso(NOW), "counts": counts, "worst": worst,
            "source": "Environment Agency flood warnings (England)",
            "url": "https://check-for-flooding.service.gov.uk/"}


def ciss() -> dict:
    """ECB Composite Indicator of Systemic Stress for the euro area (0–1)."""
    raw = get("https://data-api.ecb.europa.eu/service/data/CISS/D.U2.Z0Z.4F.EC.SS_CIN.IDX"
              "?lastNObservations=120&format=csvdata").decode()
    rows = list(csv.DictReader(io.StringIO(raw)))
    pts = [(r["TIME_PERIOD"], float(r["OBS_VALUE"])) for r in rows if r.get("OBS_VALUE")]
    return {"value": round(pts[-1][1], 4), "as_of": pts[-1][0], "max_20d": round(max(v for _, v in pts[-20:]), 4),
            "series": [round(v, 4) for _, v in pts[-90:]],
            "source": "ECB CISS (Composite Indicator of Systemic Stress, euro area)",
            "url": "https://data.ecb.europa.eu/data/datasets/CISS"}


def _median(xs: list[float]) -> float:
    s = sorted(xs)
    return s[len(s) // 2]


def epu() -> dict:
    """Baker–Bloom–Davis daily US Economic Policy Uncertainty (context anchor; derived values only)."""
    raw = get("https://www.policyuncertainty.com/media/All_Daily_Policy_Data.csv").decode()
    rows = [r for r in csv.DictReader(io.StringIO(raw)) if r.get("daily_policy_index")]
    vals = [float(r["daily_policy_index"]) for r in rows]
    last = rows[-1]
    ma7 = sum(vals[-7:]) / 7
    return {"value": round(ma7, 1), "as_of": f"{last['year']}-{int(last['month']):02d}-{int(last['day']):02d}",
            "latest_day": vals[-1], "vs_1y_median": round(ma7 / _median(vals[-365:]), 2),
            "licence": RESTRICTED_NOTE,
            "source": "Economic Policy Uncertainty index, daily US, 7-day average (Baker, Bloom & Davis)",
            "url": "https://www.policyuncertainty.com/us_daily.html"}


def gpr() -> dict:
    """Caldara–Iacoviello daily Geopolitical Risk index (context anchor; derived values only)."""
    try:
        import xlrd  # noqa: PLC0415 — optional dependency, listed in requirements.txt
    except ImportError as e:
        raise RuntimeError("xlrd not installed (pip install xlrd)") from e
    book = xlrd.open_workbook(file_contents=get("https://www.matteoiacoviello.com/gpr_files/data_gpr_daily_recent.xls", 60))
    sh = book.sheet_by_index(0)
    head = sh.row_values(0)
    col = {k: head.index(k) for k in ("DAY", "GPRD", "GPRD_MA7")}
    rows = [sh.row_values(i) for i in range(1, sh.nrows)]
    rows = [r for r in rows if isinstance(r[col["GPRD"]], float)]
    day = str(rows[-1][col["DAY"]]).split(".")[0]
    ma7 = rows[-1][col["GPRD_MA7"]]
    return {"value": round(ma7, 1), "as_of": f"{day[:4]}-{day[4:6]}-{day[6:8]}",
            "latest_day": round(rows[-1][col["GPRD"]], 1),
            "vs_1y_median": round(ma7 / _median([r[col["GPRD"]] for r in rows[-365:]]), 2),
            "licence": RESTRICTED_NOTE,
            "source": "Geopolitical Risk index, daily, 7-day average (Caldara & Iacoviello)",
            "url": "https://www.matteoiacoviello.com/gpr.htm"}


def gas_storage() -> dict | None:
    """EU gas storage fill (GIE AGSI+). Needs a free API key; skipped when AGSI_API_KEY is unset."""
    key = os.environ.get("AGSI_API_KEY")
    if not key:
        return None
    d = json.loads(get("https://agsi.gie.eu/api?type=eu&size=30", headers={"x-key": key}))
    rows = d.get("data") or []
    if not rows:
        raise RuntimeError(d.get("message") or "no data")
    cur = rows[0]
    return {"value": float(cur["full"]), "as_of": cur["gasDayStart"], "trend": float(cur.get("trend") or 0),
            "series": [float(r["full"]) for r in reversed(rows)],
            "source": "GIE AGSI+ (EU gas storage, % full)", "url": "https://agsi.gie.eu/"}


FETCHERS = {
    "vix": lambda: with_fallback(lambda: yahoo("^VIX"), lambda: fred_metric("VIXCLS", "VIX")),
    "spx": lambda: yahoo("^GSPC"),
    "ftse": lambda: yahoo("^FTSE"),
    "move": lambda: yahoo("^MOVE"),
    "us10y": lambda: with_fallback(lambda: yahoo("^TNX"), lambda: fred_metric("DGS10", "US 10y")),
    "dxy": lambda: yahoo("DX-Y.NYB"),
    "gold": lambda: yahoo("GC=F"),
    "btc": lambda: yahoo("BTC-USD"),
    "brent": lambda: with_fallback(lambda: yahoo("BZ=F"), lambda: fred_metric("DCOILBRENTEU", "Brent")),
    "ttf": lambda: yahoo("TTF=F"),
    "hy_oas": lambda: fred_metric("BAMLH0A0HYM2", "US HY OAS %"),
    "stlfsi": lambda: simple_fred("STLFSI4", "St Louis Fed Financial Stress Index", 52),
    "sahm": lambda: simple_fred("SAHMREALTIME", "Sahm rule real-time", 36),
    "t10y2y": lambda: simple_fred("T10Y2Y", "10y–2y spread", 90),
    "us_cpi": cpi_yoy,
    "quakes": quakes,
    "gdacs": gdacs,
    "swpc": swpc,
    "co2": co2,
    "oni": oni,
    "sea_ice": sea_ice,
    "global_temp": global_temp,
    "metoffice": metoffice,
    "sofr_iorb": sofr_iorb,
    "repo_ops": repo_ops,
    "icsa": icsa,
    "usdjpy": usdjpy,
    "kev": kev,
    "ea_floods": ea_floods,
    "ciss": ciss,
    "epu": epu,
    "gpr": gpr,
    "gas_storage": gas_storage,
}


def main(only: list[str] | None = None) -> int:
    prev = {}
    if OUT.exists():
        try:
            prev = json.loads(OUT.read_text()).get("metrics", {})
        except json.JSONDecodeError:
            prev = {}
    out, ok, failed = dict(prev), 0, []
    for m in out.values():  # never carry restricted raw series forward from an older file
        src = m.get("source", "") if isinstance(m, dict) else ""
        if src == "Yahoo Finance" or any(f"FRED {s} " in src for s in RESTRICTED_FRED):
            m.pop("series", None)
            m["licence"] = RESTRICTED_NOTE
    for key, fn in FETCHERS.items():
        if only and key not in only:
            continue
        try:
            m = fn()
            if m is None:  # optional source without credentials
                print(f"skip {key:12} (not configured)")
                continue
            m["fetched_at"] = iso(NOW)
            out[key] = m
            ok += 1
            print(f"ok   {key:12} {m.get('value')}")
        except Exception as e:  # noqa: BLE001
            failed.append(key)
            if key in out:
                out[key]["error"] = str(e)[:200]
            print(f"FAIL {key:12} {e}", file=sys.stderr)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"fetched_at": iso(NOW), "ok": ok, "failed": failed, "metrics": out},
                              indent=1, ensure_ascii=False))
    print(f"\n{ok} ok, {len(failed)} failed → {OUT.relative_to(ROOT)}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or None))
