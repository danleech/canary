"""Backtest the numeric leg of the judged `gilts` rubric (10y moved 40–75bp in a month = Watch, > 75bp = Alert)
on Bank of England 10y nominal par yields, using production's _level() and hysteresis margin."""
import csv, json, sys
from datetime import datetime, date
from pathlib import Path
HERE = Path(__file__).resolve().parent
CACHE, REPO, OUT = (sys.argv[1:4] if len(sys.argv) >= 4 else (str(HERE / ".cache"), str(HERE.parent.parent), str(HERE / "results")))
sys.path.insert(0, REPO + "/scripts")
import canary
rows = list(csv.reader(open(CACHE + "/boe_IUDMNPY.csv")))[1:]
pts = [(datetime.strptime(r[0], "%d %b %Y").date(), float(r[1])) for r in rows if len(r) > 1 and r[1]]
ser, prev = [], None
for i in range(21, len(pts)):
    d, y = pts[i]
    bp = abs(y - pts[i - 21][1]) * 100
    lv = canary._level(bp, 40, 75)
    if prev is not None and lv < prev:
        lv = min(prev, max(lv, canary._level(bp, 40, 75, canary.MARGIN)))
    prev = lv
    ser.append((d, "GAR"[lv], round(bp)))
def summ(a, b):
    s = [p for p in ser if a <= p[0] <= b]
    n = len(s); fl = sum(1 for k in range(1, n) if s[k][1] != s[k - 1][1])
    fa = next((p[0].isoformat() for p in s if p[1] == "R"), None)
    fw = next((p[0].isoformat() for p in s if p[1] != "G"), None)
    return {"days": n, "pct_watch": round(100 * sum(p[1] == "A" for p in s) / n, 1),
            "pct_alert": round(100 * sum(p[1] == "R" for p in s) / n, 1), "first_watch": fw, "first_alert": fa,
            "max_bp": max(p[2] for p in s), "flips": fl}
out = {"full": summ(date(2000, 2, 1), date(2026, 10, 30)), "GFC": summ(date(2007, 6, 1), date(2009, 12, 31)),
       "Covid 2020": summ(date(2020, 1, 2), date(2020, 12, 31)), "2022": summ(date(2022, 1, 4), date(2022, 12, 30)),
       "Calm 2017": summ(date(2017, 1, 3), date(2017, 12, 29))}
out["mini_budget_window"] = [(str(d), s, bp) for d, s, bp in ser if date(2022, 9, 20) <= d <= date(2022, 10, 14)]
alert_spells, cur = [], None
for d, s, bp in ser:
    if s == "R" and cur is None: cur = [d, d, bp]
    elif s == "R": cur[1] = d; cur[2] = max(cur[2], bp)
    elif cur: alert_spells.append((str(cur[0]), str(cur[1]), cur[2])); cur = None
out["alert_spells"] = alert_spells
print(json.dumps({k: v for k, v in out.items() if k != "mini_budget_window"}, indent=1, default=str))
json.dump(out, open(OUT + "/gilts_results.json", "w"), indent=1, default=str)
