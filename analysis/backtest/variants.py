"""Counterfactual rubric variants, replayed on the same history as backtest.py (production code untouched)."""
import sys, json, csv
from datetime import date, datetime, timedelta
from pathlib import Path
_HERE = Path(__file__).resolve().parent
sys.argv = ["x", str(_HERE / ".cache"), str(_HERE.parent.parent), str(_HERE / "results")]
__file__ = str(_HERE / "backtest.py")
exec(open(_HERE / "backtest.py").read().split("if __name__")[0])
L, M = canary._level, canary.MARGIN

def hyst(v, a, r, prev):
    lv = L(v, a, r)
    if lv is None: return None
    if prev is not None and lv < prev: lv = min(prev, max(lv, L(v, a, r, M)))
    return lv

def run(rule, need, start=date(2000,1,3), end=date(2026,10,30)):
    out, prev, d = [], {}, start
    while d <= end:
        if d.weekday() < 5:
            m = metrics_on(d)
            if all(k in m for k in need):
                parts = rule(m, prev)
                lv = max(x for x in parts if x is not None) if any(x is not None for x in parts) else None
                if lv is not None:
                    out.append((d, "GAR"[lv], "")); prev["_"] = lv
        d += timedelta(days=1)
    return out

def P(m, prev): return prev.get("_")
V = {
 "dollar: no 90–108 band": (lambda m, p: [hyst(abs(m["dxy"]["chg_3m_pct"]), 5, 8, P(m, p))], ["dxy"]),
 "equity: drawdown Alert at 20%": (lambda m, p: [hyst(m["vix"]["value"], 20, 30, P(m, p)), hyst(abs(m["spx"]["drawdown_pct"]), 5, 20, P(m, p))], ["vix", "spx"]),
 "equity: drawdown Watch-only (10%), Alert on VIX": (lambda m, p: [hyst(m["vix"]["value"], 20, 30, P(m, p)), min(1, hyst(abs(m["spx"]["drawdown_pct"]), 10, 1e9, P(m, p)) or 0)], ["vix", "spx"]),
 "ftse: drawdown Alert at 20%": (lambda m, p: [hyst(abs(m["ftse"]["drawdown_pct"]), 5, 20, P(m, p)), 2 if (m["ftse"]["worst_day_5d_pct"] or 0) < -4 else 1 if (m["ftse"]["worst_day_5d_pct"] or 0) < -2.5 else 0], ["ftse"]),
 "crypto: Alert at 60% drawdown": (lambda m, p: [hyst(abs(m["btc"]["drawdown_pct"]), 25, 60, P(m, p))], ["btc"]),
 "crypto: Watch 40%, Alert 70%": (lambda m, p: [hyst(abs(m["btc"]["drawdown_pct"]), 40, 70, P(m, p))], ["btc"]),
 "oil: 1-month % legs only": (lambda m, p: [hyst(m["brent"].get("chg_1m_pct"), 15, 30, P(m, p))], ["brent"]),
 "gold: 3m gain 15/25%": (lambda m, p: [hyst(m["gold"]["chg_3m_pct"], 15, 25, P(m, p)), 1 if m["gold"]["chg_3m_pct"] < -8 else None, 2 if abs(m["gold"]["chg_1w_pct"]) > 7 else None], ["gold"]),
 "funding: SOFR–IORB only": (lambda m, p: [hyst(m["sofr_iorb"]["max_5d_bp"], 10, 25, P(m, p))], ["sofr_iorb"]),
}
EP = {"GFC": (date(2007,6,1), date(2009,12,31)), "Covid": (date(2020,1,2), date(2020,12,31)), "2022": (date(2022,1,3), date(2022,12,30)),
      "Repo19": (date(2019,8,1), date(2019,12,31)), "SVB23": (date(2023,2,1), date(2023,5,31)), "Yen24": (date(2024,7,1), date(2024,9,30)),
      "Calm05-06": (date(2005,1,3), date(2006,12,29)), "Calm17": (date(2017,1,3), date(2017,12,29))}
res = {}
for name, (rule, need) in V.items():
    s = [x for x in run(rule, need) if x[2] is not None]
    full = summarise(s); eps = {k: summarise([x for x in s if a <= x[0] <= b]) for k, (a, b) in EP.items()}
    res[name] = {"full": full, "episodes": eps}
    print(f"\n{name}: W {full['pct_watch']}% A {full['pct_alert']}% longestA {full['longest_alert_bdays']} flips/yr {full['flips_per_year']} max7d {full['max_flips_7d']}")
    for k, e in eps.items():
        if e.get("days"): print(f"   {k:10} peak {e['peak']} firstA {e['first_alert']} %A {e['pct_alert']} %W {e['pct_watch']}")
# gilts rises-only variant
rows = list(csv.reader(open(RAW / "boe_IUDMNPY.csv")))[1:]
pts = [(datetime.strptime(r[0], "%d %b %Y").date(), float(r[1])) for r in rows if len(r) > 1 and r[1]]
ser, prev = [], None
for i in range(21, len(pts)):
    bp = (pts[i][1] - pts[i-21][1]) * 100
    lv = hyst(max(bp, 0), 40, 75, prev); prev = lv; ser.append((pts[i][0], "GAR"[lv], ""))
g = summarise([x for x in ser if x[0] >= date(2000,2,1)])
spells, cur = [], None
for d_, s_, _ in ser:
    if s_ == "R" and cur is None: cur = [d_, d_]
    elif s_ == "R": cur[1] = d_
    elif cur: spells.append((str(cur[0]), str(cur[1]))); cur = None
print("\ngilts rises only:", g["pct_watch"], g["pct_alert"], g["longest_alert_bdays"], spells)
res["gilts: rises only"] = {"full": g, "alert_spells": spells}
json.dump(res, open(OUT / "variants.json", "w"), indent=1, default=str)
