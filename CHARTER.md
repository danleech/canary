# Canary — Project Charter

**Status:** APPROVED v1.0 (signed off 31 Oct 2026) · **Owner:** Dan · **Date:** 31 Oct 2026

---

## 1. Purpose

A public, single-page status board that shows, at a glance, **how much attention the world's key risk signals deserve right now**. It covers finance, economy, energy, geopolitics, armed conflict, extreme weather, climate, global health, technology/cyber, humanitarian and UK-specific signals.

Each signal is a red/amber/green indicator with a trend arrow and three lines of plain-English context. A scheduled cloud Claude task re-assesses everything 4× a day.

**One-line pitch:** *The canary in the coal mine for the state of the world, refreshed every six hours.*

## 2. Audience & positioning

- **Primary:** a curious, informed public (professionals, news-literate generalists) who want a calm cross-domain overview instead of doom-scrolling.
- **Lens:** global, UK-flavoured. Mostly global signals, plus a dedicated UK panel.
- **Differentiation:** existing trackers each cover one domain (Fear & Greed, CFR Conflict Tracker, GDACS, WHO DONs). Canary is cross-domain, glanceable, explains why each signal has its current state, and is transparent about its method.

## 3. Status semantics (the core design decision)

Colour means **attention level**. It is not a forecast and it is not advice.

| Status | Label | Meaning |
|---|---|---|
| 🟢 | **Normal** | Within normal range. Background noise. |
| 🟠 | **Watch** | Elevated or deteriorating. Worth keeping an eye on. |
| 🔴 | **Alert** | Acute or material risk happening now. If it could affect you, look into it. |
| ⚪ | **Stale** | Not verified within the freshness window (shown automatically). |

- **Trend arrow:** ↑ worsening · → stable · ↓ improving (direction of risk, not of the number).
- **"What this means for you":**
  - **Weather, health, travel, UK security:** may be prescriptive, but only by pointing to official guidance (Met Office, FCDO, UKHSA, MI5 threat level, WHO).
  - **Finance and economy:** strictly descriptive ("markets are in a stress regime"). Never "buy", "sell", "switch" or "consider moving assets".
- **Consistency rules:**
  1. Every signal has a written rubric with numeric thresholds wherever possible.
  2. **Hysteresis:** status only changes when evidence clearly crosses a threshold, and quantitative de-escalation needs a margin (e.g. VIX must fall below 27, not 30, to leave Alert).
  3. Every change records a one-line reason and its sources.
  4. Status can move at most one step per run unless a hard threshold or an official trigger fires (e.g. WHO declares a PHEIC).

## 4. Scope: signal catalogue (v1, ~68 signals, 11 domains)

Final rubrics are written during the build. **D** = refreshed once daily; everything else refreshes every run.

1. **Markets** (8): Equity stress (S&P 500 drawdown + VIX) · FTSE 100 · Bond volatility (MOVE / US 10y) · Credit spreads (US HY OAS) · Dollar (DXY) · Banking-system stress · Gold (safe-haven demand) · Crypto stress
2. **Economy** (7): US recession risk (curve, Sahm rule) · US inflation · Euro-area growth · China economy · Central-bank stance (Fed/ECB/BoJ) · Sovereign debt stress (US/Japan/France/Italy) **D** · Global PMI **D**
3. **Energy & commodities** (6): Brent crude · European gas (TTF) · Shipping chokepoints (Red Sea/Suez/Hormuz/Panama) · Freight rates · Food prices (FAO index) **D** · Critical minerals / rare earths **D**
4. **Geopolitics** (7): US–China / Taiwan Strait · Russia–NATO · Iran nuclear programme · Korean peninsula · Trade war / tariffs · Sanctions regime · Major election / political instability
5. **Armed conflict** (8): Russia–Ukraine · Israel–Gaza / regional · Sudan · DRC (east) · Sahel · Myanmar · India–Pakistan · Nuclear risk (posture, rhetoric, testing)
6. **Extreme weather & hazards** (9): Atlantic tropical cyclones · W. Pacific / Indian Ocean cyclones · Global heat extremes · Wildfires · Major floods (GDACS) · Earthquakes & tsunami (USGS) · Volcanic / aviation ash · Drought **D** · Space weather (NOAA Kp)
7. **Climate & environment** (5, all **D**): Global temperature anomaly · Sea ice (Arctic/Antarctic) · Atmospheric CO₂ · ENSO state · Coral bleaching
8. **Global health** (6): WHO emergencies / PHEIC · H5N1 avian flu · Mpox · Measles / vaccine-preventable outbreaks · Cholera & dengue **D** · Novel / unexplained outbreaks
9. **Technology & cyber** (5): Major cyber incidents / ransomware · Internet & cloud outages · Undersea cables & GNSS jamming · Semiconductor supply **D** · AI incidents & governance **D**
10. **Humanitarian** (3, all **D**): Famine (IPC Phase 5) · Forced displacement · Civil unrest
11. **UK watch** (7): BoE rate & UK inflation · Gilt market stress · UK energy price cap **D** · Met Office warnings · NHS / respiratory pressure (UKHSA) · UK terrorism threat level · Major strikes / disruption

**Headline "World State" index:** a weighted aggregate (Alert = 2, Watch = 1, domain-weighted, scaled 0–100) shown as one number plus colour at the top. The formula is published on the methodology page.

## 5. Non-goals (v1)

- No investment, medical or legal advice. No trading signals.
- No user accounts, comments, personalisation or paid tier.
- No forecasting or probability estimates. The board describes the current state.
- No real-time (sub-hourly) updates. No mobile app (the site is responsive).
- No coverage of individual named private people.

## 6. Features at launch

- Single dense page: domain panels in a responsive grid. Each signal row shows dot, name, key value, arrow and age. Click or tap expands to **Why it matters / What drives it / Why it's at this state / What this means for you** plus sources.
- **"Changed in last 24h"** highlight and strip at the top.
- **History + sparklines:** every status change and key value is appended to history, shown as per-signal sparklines and a status timeline.
- **Atom feed** of status changes (`/feed.xml`).
- **World State index** at the top.
- **Methodology page:** rubrics, thresholds, sources, cadence, the AI-assessment disclosure and disclaimers.
- Staleness handling: any signal not verified for more than 14h (or 36h for **D** signals) turns ⚪ automatically, computed client-side.
- Accessibility: colour is never the only cue (labels and shapes are shown too), WCAG AA contrast, keyboard navigable.

## 7. Design direction

**Editorial light:** FT/Economist calm. Light default (with dark mode), serif display headings, a crisp sans for body text, tabular numerals, hairline rules and tight information density. RAG colours are muted and editorial rather than traffic-light neon. The page should feel like a well-set front page, not a dashboard template.

## 8. Architecture

```
GitHub repo (public) ──► Cloudflare Pages (auto-deploy on push) ──► canary.<domain>
   │
   ├─ site/                 static HTML/CSS/vanilla JS (no framework, no build step)
   │   └─ reads data/status.json, data/history.json, data/metrics.json
   ├─ data/                 the "database": JSON files, committed
   ├─ signals/catalogue.yaml  signal definitions + rubrics (source of truth)
   ├─ scripts/
   │   ├─ fetch_metrics.py  pulls hard numbers from open APIs → data/metrics.json
   │   ├─ validate.py       JSON-schema + sanity checks; blocks bad commits
   │   └─ build_feed.py     regenerates feed.xml + World State index
   ├─ .github/workflows/metrics.yml  runs fetch_metrics 4×/day, ~30 min before Claude
   ├─ CLAUDE.md             editorial rules for any Claude session in the repo
   └─ .claude/skills/canary-update/SKILL.md  the update procedure + rubric usage
```

**Hybrid data:**
- A free GitHub Action fetches numeric data from open, no-key APIs where possible: USGS, NOAA SWPC, NOAA CO₂, GDACS, NSIDC, Met Office feeds, and FRED with a free API key.
- The Claude task reads that file, then web-searches and fetches pages for qualitative signals and context. It applies the rubrics and writes `status.json`.
- If a metric fetch fails, Claude falls back to web sources and marks the value's provenance.

**Scheduled cloud task:**
- **When:** 4× daily at about 05:40, 11:40, 17:40 and 23:40 UK time.
- **Each run:** pull repo → run `canary-update` skill → validate → commit and push → Cloudflare redeploys.
- **Safeguards:** a run that fails validation commits nothing, so the site keeps the last good state.
- **Run log:** each run appends a short entry to `data/runs.json` (time, signals changed, errors).

## 9. Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Status flicker / inconsistent judgement | High | High | Rubrics, hysteresis, one-step rule, change reasons |
| Hallucinated facts or numbers | Med | High | Every claim needs a source URL from this run; numbers from API where possible; validator rejects sourceless signals |
| Perceived financial advice (FCA) | Med | High | Descriptive-only finance copy; disclaimers; banned-phrase lint in validator |
| Run failure → stale site | Med | Med | Last-good state persists; client-side ⚪ stale flag; run log |
| Usage cost of 68 signals × 4/day | Med | Med | **D** tier; reuse metrics file; skip search for unchanged quantitative signals |
| Distressing content (war, health) | Med | Med | Neutral, factual tone; no graphic detail; no casualty speculation |
| Personal reputation (public, AI-written) | Low | Med | Methodology page, transparent AI disclosure, contact for corrections |
| Bias in conflict/political framing | Med | Med | Neutral wording rules in CLAUDE.md; multiple sources on contested items |

## 10. Success criteria (first 30 days)

- ≥ 95% of scheduled runs complete and deploy (from the run log).
- Zero runs publish invalid JSON or a signal without a source.
- At most ~3 status flips per signal per week, unless reality genuinely moved.
- Page loads in under 1s (Lighthouse ≥ 95 performance and accessibility).
- Dan reviews 10 random signals and agrees with ≥ 8 of the statuses.

## 11. Name & domain

Dan's favourite, **canary.ai**, is registered (taken). I checked these via registry (RDAP) lookups on 31 Oct; they **appear unregistered**, but verify at a registrar before buying.

| Option | Domain | Notes |
|---|---|---|
| **Canary** | **coalmine.live** | Strongest metaphor fit ("canary in the coalmine, live") |
| Canary | coalmine.watch | Same idea; .watch suits a status board |
| The Canary | thecanary.live / thecanary.watch | ⚠ "The Canary" is an existing UK political news site, so there's brand-confusion risk |
| Canary | worldcanary.org / worldcanary.com | Clear, global, .com available |
| Sea Change | seachange.watch | Elegant; the meaning is about shifts rather than danger |
| Windshift | windshift.live | Short, distinctive, weather-flavoured |
| Bellwether | bellwether.live | Strong word; .watch is taken |
| Canary Says | canarysays.com | Friendly, .com available |

**Recommendation:** brand it **Canary** on **coalmine.live** (or **worldcanary.com** if you want a .com). Launch first on the free `*.pages.dev` URL and attach the domain when bought.

## 12. What Dan needs to do (prerequisites)

1. **Connect GitHub to Claude** (claude.ai → Settings → Connectors/GitHub). This is currently not linked, and both the build and the scheduled task need it to push.
2. **Create an empty public repo** named `canary` and tell me `owner/canary`.
3. **Cloudflare:** create a free account, then Pages → *Connect to Git* → select the repo (build command none, output dir `site`). About 5 minutes, with steps in the README.
4. *(Optional)* A free **FRED API key** stored as a GitHub Actions secret `FRED_API_KEY`. Without it, some macro series fall back to web search.
5. *(Later)* Buy the domain and add it in Cloudflare Pages.

## 13. Delivery plan (one build session after sign-off)

1. Repo scaffold, CLAUDE.md, `canary-update` skill, signal catalogue with rubrics
2. Metrics fetcher + GitHub Action + validator + feed builder
3. Static site (board, expansion panels, sparklines, World State, changes strip, methodology page, light/dark)
4. First full assessment run, so the site launches with real, sourced statuses
5. Visual QA in a headless browser at desktop and phone widths
6. Push to GitHub; create the 4×/day scheduled cloud task; trigger one test run
7. Handover note: how to tweak rubrics, add signals and pause the task

## 14. Decisions at sign-off

- Working name **Canary**; domain decided later (launch on `*.pages.dev`).
- No push alerts in v1.
- At the first run, an **Ebola & haemorrhagic fevers** signal was added (72 signals total), and the sovereign-debt rubric was given an explicit France–Bund > 150bp Alert threshold. The original catalogue had no category for either situation.
