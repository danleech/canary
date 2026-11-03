# Rubric backtest

Replays the board's production rule code (`suggest()` in `scripts/canary.py`) once per business day from 2000 to 2026, on historical data rebuilt as it was known each day (weekly and monthly series lagged to their usual release dates), with hysteresis carried from the previous day. Charter §17, next step 1. First run 3 Nov 2026 on catalogue v1.3.

```bash
python analysis/backtest/fetch.py      # raw series → analysis/backtest/.cache/ (git-ignored)
python analysis/backtest/backtest.py   # 14 measured signals → results/backtest_*.json, measured_load.json
python analysis/backtest/gilts.py      # numeric leg of the judged `gilts` rubric (BoE 10y) → results/gilts_results.json
python analysis/backtest/variants.py   # proposed rubric changes on the same history → results/variants.json
```

- **Floors only.** The live assessor can raise statuses, so the board would sit at or above these levels.
- **Tested:** equity stress, FTSE, bond volatility, dollar, banking stress, funding stress, yen carry, jobless claims, gold, crypto, US recession, US inflation, oil, EU gas. **Not tested:** credit spreads (FRED's ICE BofA history now starts Nov 2023), hazard and climate rules, judged and published signals.
- **Data:** Yahoo Finance (the production source for market series), FRED, the ECB (CISS) and the Bank of England. Claims and CPI are today's revised figures; Sahm is FRED's real-time series; Brent is the EIA spot price.
- **Licensing:** raw series stay in the git-ignored cache. `results/` holds only derived statistics (status letters, shares of days, dates, counts), as CLAUDE.md requires for sources without an open licence.

The write-up, with findings and proposed rubric changes for after the 2 Dec freeze, is the "Canary rubric backtest" doc in the claude.ai project.
