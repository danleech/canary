#!/usr/bin/env python3
"""Backtest Canary's metric rubrics against history (charter §17, next step 1).

Replays the PRODUCTION rule code (canary.suggest) day by day over historical data, with each day's
metrics rebuilt as they would have been known that day (weekly/monthly series lagged to their usual
release dates), and hysteresis carried from the previous day's floor. Only the metric floors are
tested: in production the assessor can raise a status above its floor.

Usage: python analysis/backtest/fetch.py && python analysis/backtest/backtest.py   (optional args: CACHE_DIR REPO_DIR OUT_DIR)
Raw series are third-party data (Yahoo Finance, FRED, ECB) used for internal analysis only; only
derived results (dates, counts) go into OUT_DIR.
"""
from __future__ import annotations

import bisect
import csv
import json
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
RAW, REPO, OUT = (Path(a) for a in (sys.argv[1:4] if len(sys.argv) >= 4 else (HERE / ".cache", HERE.parent.parent, HERE / "results")))
sys.path.insert(0, str(REPO / "scripts"))
import canary  # noqa: E402  (production rules)

D = date.fromisoformat


# ───────────── loading ─────────────

def yahoo(sym: str) -> tuple[list[date], list[float]]:
    f = RAW / ("yahoo_" + "".join(c if c.isalnum() else "_" for c in sym) + ".json")
    r = json.loads(f.read_text())["chart"]["result"][0]
    out = {}
    for t, c in zip(r["timestamp"], r["indicators"]["quote"][0]["close"]):
        if c is not None:
            out[datetime.fromtimestamp(t, timezone.utc).date()] = float(c)
    ks = sorted(out)
    return ks, [out[k] for k in ks]


def fred(sid: str) -> tuple[list[date], list[float]]:
    rows = list(csv.reader((RAW / f"fred_{sid}.csv").read_text().splitlines()))[1:]
    pts = [(D(r[0]), float(r[1])) for r in rows if len(r) > 1 and r[1] not in ("", ".")]
    return [p[0] for p in pts], [p[1] for p in pts]


def ecb_ciss() -> tuple[list[date], list[float]]:
    rows = list(csv.DictReader((RAW / "ecb_ciss.csv").read_text().splitlines()))
    pts = sorted((D(r["TIME_PERIOD"]), float(r["OBS_VALUE"])) for r in rows if r.get("OBS_VALUE"))
    return [p[0] for p in pts], [p[1] for p in pts]


class Series:
    """A dated series with as-of lookup and the same derived statistics as fetch_metrics.series_stats."""

    def __init__(self, dates, vals, lag_days: int = 0):
        self.d = [x + timedelta(days=lag_days) for x in dates]  # date the value became known
        self.v = vals

    def idx(self, day: date) -> int | None:
        i = bisect.bisect_right(self.d, day) - 1
        return i if i >= 0 else None

    def stats(self, day: date) -> dict | None:
        i = self.idx(day)
        if i is None or i < 63:
            return None
        v = self.v
        last = v[i]
        hi = max(v[max(0, i - 251):i + 1])

        def back(n):
            return v[i - n]
        week = v[i - 5:i + 1]
        daily = [(week[k] / week[k - 1] - 1) * 100 for k in range(1, len(week)) if week[k - 1]]
        return {"value": last, "drawdown_pct": (last / hi - 1) * 100,
                "chg_1w_pct": (last / back(5) - 1) * 100, "chg_1m_pct": (last / back(21) - 1) * 100,
                "chg_3m_pct": (last / back(63) - 1) * 100, "chg_1m_abs": last - back(21),
                "worst_day_5d_pct": min(daily) if daily else None}

    def value(self, day: date):
        i = self.idx(day)
        return None if i is None else self.v[i]


# ───────────── series (production sources where history exists) ─────────────
S = {
    "vix": Series(*yahoo("^VIX")), "spx": Series(*yahoo("^GSPC")), "ftse": Series(*yahoo("^FTSE")),
    "move": Series(*yahoo("^MOVE")), "us10y": Series(*fred("DGS10")), "dxy": Series(*yahoo("DX-Y.NYB")),
    "gold": Series(*yahoo("GC=F")), "btc": Series(*yahoo("BTC-USD")), "ttf": Series(*yahoo("TTF=F")),
    "usdjpy": Series(*yahoo("JPY=X")),
    "brent": Series(*fred("DCOILBRENTEU")),           # EIA spot via FRED (production: ICE futures, FRED fallback)
    "stlfsi": Series(*fred("STLFSI4"), lag_days=6),   # week ending Friday, published the next Thursday
    "ciss": Series(*ecb_ciss(), lag_days=3),
    "repo": Series(*fred("RPONTSYD")),
}
sahm_d, sahm_v = fred("SAHMREALTIME")
S["sahm"] = Series(sahm_d, sahm_v, lag_days=35)      # month M, released with the jobs report early M+1
cpi_d, cpi_v = fred("CPIAUCSL")
yoy = [(cpi_v[i] / cpi_v[i - 12] - 1) * 100 for i in range(12, len(cpi_v))]
S["cpi"] = Series(cpi_d[12:], yoy, lag_days=44)       # month M, released mid M+1
icsa_d, icsa_v = fred("ICSA")
avg4 = [sum(icsa_v[i - 3:i + 1]) / 4 for i in range(3, len(icsa_v))]
above = [None] * 51 + [(avg4[i] / min(avg4[i - 51:i + 1]) - 1) * 100 for i in range(51, len(avg4))]
S["icsa_avg4"] = Series(icsa_d[3:], avg4, lag_days=5)  # week ending Saturday, published Thursday
S["icsa_up"] = Series(icsa_d[3:], above, lag_days=5)
# SOFR minus the Fed's reserve rate (IORB from 29 Jul 2021; IOER before), bp
sofr_d, sofr_v = fred("SOFR")
iorb, ioer = Series(*fred("IORB")), Series(*fred("IOER"))
spread = []
for d_, v_ in zip(sofr_d, sofr_v):
    r = iorb.value(d_) if d_ >= date(2021, 7, 29) else ioer.value(d_)
    spread.append(None if r is None else (v_ - r) * 100)
S["sofr_iorb"] = Series(sofr_d, spread)


def max5(s: Series, day: date):
    i = s.idx(day)
    if i is None or i < 4:
        return None
    vals = [x for x in s.v[i - 4:i + 1] if x is not None]
    return max(vals) if vals else None


def metrics_on(day: date) -> dict:
    m: dict = {}
    for k in ("vix", "move", "brent", "ttf"):
        st = S[k].stats(day) if k in ("brent",) else None
        v = S[k].value(day)
        if v is not None and S[k].idx(day) is not None and (day - S[k].d[S[k].idx(day)]).days <= 7:
            m[k] = {"value": v}
            if k == "brent" and st:
                m[k]["chg_1m_pct"] = st["chg_1m_pct"]
    for k in ("spx", "ftse", "dxy", "gold", "btc", "usdjpy", "us10y"):
        st = S[k].stats(day)
        if st and (day - S[k].d[S[k].idx(day)]).days <= 7:
            m[k] = st
    for k in ("stlfsi", "ciss", "sahm"):
        v = S[k].value(day)
        if v is not None and (day - S[k].d[S[k].idx(day)]).days <= (45 if k == "sahm" else 14):
            m[k] = {"value": v}
    i = S["cpi"].idx(day)
    if i is not None and i >= 4 and (day - S["cpi"].d[i]).days <= 45:
        v = S["cpi"].v
        m["us_cpi"] = {"value": v[i], "rising_3m": v[i] > v[i - 1] > v[i - 2] > v[i - 3]}
    a4, up = S["icsa_avg4"].value(day), S["icsa_up"].value(day)
    if a4 is not None and up is not None:
        m["icsa"] = {"avg4": a4, "above_low_pct": up}
    sp, rp = max5(S["sofr_iorb"], day), max5(S["repo"], day)
    if sp is not None or rp is not None:
        cur = S["sofr_iorb"].value(day)
        m["sofr_iorb"] = {"value": cur, "max_5d_bp": sp}
        m["repo_ops"] = {"value": S["repo"].value(day), "max_5d": rp}
    return m


SIGNALS = ["equity-stress", "ftse", "bond-volatility", "dollar", "banking-stress", "funding-stress",
           "yen-carry", "jobless-claims", "gold", "crypto", "us-recession", "us-inflation", "oil", "eu-gas"]
NEEDS = {  # metrics that must be present for a signal's day to count (all its rules testable)
    "equity-stress": ["vix", "spx"], "ftse": ["ftse"], "bond-volatility": ["move", "us10y"], "dollar": ["dxy"],
    "banking-stress": ["stlfsi", "ciss"], "funding-stress": ["sofr_iorb"], "yen-carry": ["usdjpy"],
    "jobless-claims": ["icsa"], "gold": ["gold"], "crypto": ["btc"], "us-recession": ["sahm"],
    "us-inflation": ["us_cpi"], "oil": ["brent"], "eu-gas": ["ttf"],
}
LETTER = {"green": "G", "amber": "A", "red": "R"}


def replay(start: date, end: date) -> dict[str, list[tuple[date, str]]]:
    """Business-day replay with hysteresis from the previous day's floor."""
    out: dict[str, list] = defaultdict(list)
    prev: dict[str, int | None] = {s: None for s in SIGNALS}
    day = start
    while day <= end:
        if day.weekday() < 5:
            m = metrics_on(day)
            for sid in SIGNALS:
                if not all(k in m for k in NEEDS[sid]):
                    continue
                if sid == "funding-stress" and m["sofr_iorb"].get("max_5d_bp") is None:
                    continue
                sug = canary.suggest(sid, m, prev[sid])
                if sug is None:
                    continue
                prev[sid] = canary.LEVEL[sug["status"]]
                out[sid].append((day, LETTER[sug["status"]], sug["basis"]))
        day += timedelta(days=1)
    return out


def summarise(series: list) -> dict:
    if not series:
        return {"days": 0}
    n = len(series)
    cnt = defaultdict(int)
    flips, flip_days = 0, []
    first = {"A": None, "R": None}
    for k, (d_, s, _) in enumerate(series):
        cnt[s] += 1
        if s in ("A", "R") and first["A"] is None:
            first["A"] = d_
        if s == "R" and first["R"] is None:
            first["R"] = d_
        if k and s != series[k - 1][1]:
            flips += 1
            flip_days.append(d_)
    # most flips inside any 7-calendar-day window (charter target: ≤ ~3 per week)
    mx, j = 0, 0
    for i, d_ in enumerate(flip_days):
        while flip_days[j] < d_ - timedelta(days=6):
            j += 1
        mx = max(mx, i - j + 1)
    # longest Alert spell (business days)
    best = run = 0
    for _, s, _ in series:
        run = run + 1 if s == "R" else 0
        best = max(best, run)
    peak = "R" if cnt["R"] else "A" if cnt["A"] else "G"
    last_alert = max((d_ for d_, s, _ in series if s == "R"), default=None)
    return {"from": series[0][0].isoformat(), "to": series[-1][0].isoformat(), "days": n,
            "pct_normal": round(100 * cnt["G"] / n, 1), "pct_watch": round(100 * cnt["A"] / n, 1),
            "pct_alert": round(100 * cnt["R"] / n, 1), "peak": peak,
            "first_watch_or_alert": first["A"].isoformat() if first["A"] else None,
            "first_alert": first["R"].isoformat() if first["R"] else None,
            "last_alert": last_alert.isoformat() if last_alert else None,
            "flips": flips, "flips_per_year": round(flips / (n / 252), 1), "max_flips_7d": mx,
            "longest_alert_bdays": best}


EPISODES = {
    "GFC 2007–09": (date(2007, 6, 1), date(2009, 12, 31)),
    "Covid 2020": (date(2020, 1, 2), date(2020, 12, 31)),
    "2022 (inflation, Ukraine, gilts)": (date(2022, 1, 3), date(2022, 12, 30)),
    "Repo spike 2019": (date(2019, 8, 1), date(2019, 12, 31)),
    "SVB 2023": (date(2023, 2, 1), date(2023, 5, 31)),
    "Yen carry unwind 2024": (date(2024, 7, 1), date(2024, 9, 30)),
    "Calm 2005–06": (date(2005, 1, 3), date(2006, 12, 29)),
    "Calm 2017": (date(2017, 1, 3), date(2017, 12, 29)),
}
ANCHORS = [  # widely documented market events, for lead/lag reading
    ("2007-08-09", "BNP Paribas freezes funds"), ("2008-03-14", "Bear Stearns rescue"),
    ("2008-09-15", "Lehman Brothers bankruptcy"), ("2009-03-09", "S&P 500 low"),
    ("2019-09-17", "US repo rate spike"), ("2020-02-24", "Covid sell-off begins"),
    ("2020-03-23", "Fed unlimited QE; equity low"), ("2022-02-24", "Russia invades Ukraine"),
    ("2022-09-23", "UK mini-budget"), ("2022-09-28", "BoE gilt intervention"),
    ("2023-03-10", "SVB failure"), ("2024-08-05", "Yen carry unwind sell-off"),
]

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    full = replay(date(2000, 1, 3), date(2026, 10, 30))
    res = {"generated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
           "method": "production canary.suggest() replayed daily on historical data; metric floors only",
           "full_span": {s: summarise(full[s]) for s in SIGNALS}, "episodes": {}}
    for name, (a, b) in EPISODES.items():
        res["episodes"][name] = {s: summarise([p for p in full[s] if a <= p[0] <= b]) for s in SIGNALS}
    # status on each anchor date
    res["anchors"] = {}
    for d_, label in ANCHORS:
        dd = D(d_)
        row = {}
        for s in SIGNALS:
            pts = [p for p in full[s] if p[0] <= dd]
            if pts and (dd - pts[-1][0]).days <= 5:
                row[s] = pts[-1][1]
        res["anchors"][f"{d_} {label}"] = row
    # compact daily ribbons per episode (one letter per business day) for charts
    res["ribbons"] = {name: {s: "".join(p[1] for p in full[s] if a <= p[0] <= b) for s in SIGNALS}
                      for name, (a, b) in list(EPISODES.items())[:3]}
    (OUT / "backtest_results.json").write_text(json.dumps(res, indent=1))
    # monthly status grid for the full span (worst status in each month)
    grid = {}
    for s in SIGNALS:
        by_m = defaultdict(str)
        for d_, st, _ in full[s]:
            k = d_.strftime("%Y-%m")
            by_m[k] = max(by_m[k], st, key=lambda x: "GAR".find(x) if x else -1)
        grid[s] = dict(by_m)
    (OUT / "backtest_monthly.json").write_text(json.dumps(grid))
    # how many of the continuous measured signals sit at Alert / Watch on an average day, by year and quarter
    core = ["equity-stress", "ftse", "dollar", "banking-stress", "yen-carry", "jobless-claims", "gold", "us-recession",
            "us-inflation", "oil"]
    by_day = defaultdict(dict)
    for s_ in core:
        for d_, st, _ in full[s_]:
            by_day[d_][s_] = st
    yr, qt = defaultdict(list), defaultdict(list)
    for d_ in sorted(by_day):
        if len(by_day[d_]) == len(core):
            v = list(by_day[d_].values())
            ra = (sum(x == "R" for x in v), sum(x == "A" for x in v))
            yr[d_.year].append(ra)
            qt[f"{d_.year}-Q{(d_.month - 1) // 3 + 1}"].append(ra)
    mean = lambda xs: (round(sum(x[0] for x in xs) / len(xs), 2), round(sum(x[1] for x in xs) / len(xs), 2))  # noqa: E731
    (OUT / "measured_load.json").write_text(json.dumps({"core": core, "yearly": {y: mean(v) for y, v in sorted(yr.items())},
                                                        "quarterly": {q: mean(v) for q, v in sorted(qt.items())}}, indent=1))
    print("ok", {s: res["full_span"][s].get("days") for s in SIGNALS})
