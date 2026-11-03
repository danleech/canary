#!/usr/bin/env python3
"""Download the historical series the backtest needs into analysis/backtest/.cache/ (git-ignored).

The raw series belong to their publishers (Yahoo Finance, FRED and the series' owners, the ECB, the Bank of
England) and are never committed: only derived results go into results/ (see CLAUDE.md, Licensing).

  python analysis/backtest/fetch.py
"""
import time
import urllib.parse
import urllib.request
from pathlib import Path

CACHE = Path(__file__).resolve().parent / ".cache"
UA = "Mozilla/5.0 (compatible; CanaryBot/1.1; +https://canary.danleech.com/methodology)"
YAHOO = ["^VIX", "^GSPC", "^FTSE", "^MOVE", "DX-Y.NYB", "GC=F", "TTF=F", "BTC-USD", "BZ=F", "JPY=X"]
FRED = ["VIXCLS", "DGS10", "STLFSI4", "SAHMREALTIME", "T10Y2Y", "CPIAUCSL", "DCOILBRENTEU", "ICSA", "DEXJPUS",
        "SOFR", "IORB", "IOER", "RPONTSYD"]


def get(url: str) -> bytes:
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=90) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"{url}: {last}")


def main() -> None:
    CACHE.mkdir(exist_ok=True)
    for s in YAHOO:
        name = "yahoo_" + "".join(c if c.isalnum() else "_" for c in s) + ".json"
        q = urllib.parse.quote(s)
        (CACHE / name).write_bytes(get(f"https://query1.finance.yahoo.com/v8/finance/chart/{q}"
                                       "?period1=0&period2=9999999999&interval=1d"))
        print("ok", s)
    for s in FRED:
        (CACHE / f"fred_{s}.csv").write_bytes(get(f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={s}"))
        print("ok", s)
    (CACHE / "ecb_ciss.csv").write_bytes(get("https://data-api.ecb.europa.eu/service/data/CISS/"
                                             "D.U2.Z0Z.4F.EC.SS_CIN.IDX?format=csvdata"))
    print("ok CISS")
    (CACHE / "boe_IUDMNPY.csv").write_bytes(get(
        "https://www.bankofengland.co.uk/boeapps/database/_iadb-fromshowcolumns.asp?csv.x=yes&SeriesCodes=IUDMNPY"
        "&CSVF=TN&UsingCodes=Y&Datefrom=01/Jan/2000&Dateto=now"))
    print("ok BoE 10y gilt")


if __name__ == "__main__":
    main()
