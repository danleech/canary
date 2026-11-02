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

**Headline "World State" index:** a weighted aggregate (Alert = 2, Watch = 1, domain-weighted, scaled 0–100) shown as one number plus colour at the top. The formula is published on the methodology page. *(Changed on 2 Nov 2026: equal domain weights, with signals in one situation counted once per domain. See §17.)*

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
- ~~Dan reviews 10 random signals and agrees with ≥ 8 of the statuses.~~ Replaced on 2 Nov 2026 (§17): it calibrated the board to the same priors that shaped the catalogue.
- **External agreement (replaces the line above).** At day 30, compare Canary with independent trackers on the same dates: Crisis Group CrisisWatch (conflict and geopolitics deteriorations), IPC/FEWS NET (famine), WHO Disease Outbreak News (health), GDACS red alerts (hazards). Target: every event those trackers flag at their top level appears on Canary at Watch or above, with no unexplained Alerts. Record disagreements and what they taught.
- **Judgement share is visible.** Every status shows its basis, and the share of AI judgements is published on the board and in `runs.json`.

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

## 15. v1.1 — agent interface and catalogue expansion (1 Nov 2026)

Dan asked for Canary to be optimised for AI/LLM agents: a shortcut to the key information without burning tokens. Changes:

- **Pre-rendered HTML.** The board, methodology rubrics and per-signal pages are rendered at build time, so fetchers that don't run JavaScript see the real board (before this, they saw "Loading…" and an error message).
- **Layered, token-budgeted outputs:** `now.md` (~1k tokens), `status.md` (~3k), `s/{id}.md|json` and citable `s/{id}` pages, `api/v1/{meta,status,changes,catalogue,schema}.json`, `llms.txt`, `openapi.json`, `sitemap.xml`, `robots.txt` (with Content Signals), a real `404.html`.
- **MCP server** at `/mcp` (Pages Function, read-only, three tools) and Markdown content negotiation for `/` and `/s/{id}`.
- **Atom feed** kept but demoted: entries link to `/s/{id}`, carry the current state, use valid tag URIs, and a rolling daily digest entry carries the brief.
- **New schema fields:** `situations` (cross-domain events grouping signals), `emerging` (max 3 risks outside the catalogue), per-signal `rubric_hit`, catalogue `horizon` (acute/seasonal/chronic). Machine outputs use the public vocabulary (alert/watch/normal; worsening/stable/improving) plus `as_of`, `valid_until` and `stale_after`.
- **Safety:** `apply` rejects instruction-like text, invisible Unicode and URLs in prose before writing; source domains outside `trusted_sources.yaml` are flagged in the run log.
- **Data licensing:** `metrics.json` no longer republishes raw series from restricted sources (Yahoo Finance, ICE BofA, Cboe VIX, EPU/GPR); only latest values and derived statistics. Earlier commits still contain the old series in git history.
- **Licence:** Canary's statuses and text are CC BY 4.0.
- **17 new signals (89 total):** dollar funding stress, private credit, yen & carry trade, US jobless claims, emerging-market stress, fertiliser supply, nuclear plant safety, Europe hybrid attacks, Gulf / US–Iran war (split out of "Israel, Gaza & region"), other armed conflicts, cold waves & winter storms, respiratory variants & flu, medicine shortages, exploited vulnerabilities (CISA KEV), humanitarian funding gap, GB energy supply margins, UK flood warnings. Banking stress gained the ECB CISS; "Cholera & dengue" widened to mosquito-borne disease; drought now covers monsoon failure. New metrics: SOFR–IORB, Fed repo operations, initial claims, USD/JPY, CISA KEV, EA floods, ECB CISS; GPR and EPU as context anchors.
- **Open decisions for Dan:** World State still counts every signal (one event can lift several); `ai-train=yes` in robots.txt; CC BY 4.0 as the licence.

## 16. v1.2 — sentiment track (1 Nov 2026)

Dan asked for a sentiment track for global issues and how the intelligence could be sourced. The track shows how the news and the public *feel* about the issues Canary rates, next to how Canary rates them. It is **measured, not judged**: a script computes it from open data, it has no red/amber/green colours, it never changes a status and the World State index ignores it.

**Sources evaluated (tested live on 1 Nov 2026):**

| Source | What it measures | Verdict |
|---|---|---|
| GDELT Global Knowledge Graph bulk files | Tone and volume of world online news, English plus ~65 machine-translated languages, every 15 min | **Used.** Free to reuse with a citation, no key. The bulk files avoid GDELT's DOC API, which returned HTTP 429 to shared cloud IPs in testing. |
| OECD composite consumer confidence | Household mood, ~50 economies, monthly (long-run average = 100) | **Used**, latest values and derived statistics only (national survey inputs can be third-party). |
| EPU, GPR, VIX | Text- and market-based uncertainty | **Reused** from `metrics.json` (VIX now carries a 1-year percentile). |
| Opinion polls (Ipsos What Worries the World, YouGov issues tracker, ONS OPN) | What people say worries them | **Not automated.** The most valid measure of public concern, but no open machine-readable feed. Candidate for a monthly reading maintained by the Claude run. |
| Social media (X, Reddit, Bluesky) | Online chatter | Rejected: paid or restricted access, unrepresentative samples. |
| Search attention (Google Trends, Wikipedia pageviews) | What people look up | Rejected for now: no stable open Google API; Wikimedia's API rate-limited the cloud IP and asks for contact details in the User-Agent. |
| Prediction markets | Crowd probabilities | Rejected: forecasts are a charter non-goal. |
| Claude-judged sentiment | — | Rejected: circular (Claude already reads the news for statuses) and not reproducible. |

**Method:** nine issues (economy, war & security, energy, trade, climate change, disasters, health, cyber & tech, migration) are defined by GDELT themes in `signals/sentiment.yaml`, each linked to Canary domains. Four 15-minute samples a day per stream (00/06/12/18 UTC, ~7–13k articles a day) are pooled into 7-day windows and ranked against every 7-day window in the previous 180 days, so each issue is compared only with itself. History was backfilled for 200 days at launch.

**Files:** `scripts/fetch_sentiment.py` (runs in the metrics workflow, `continue-on-error`), `signals/sentiment.yaml`, `site/data/sentiment.json`, pre-rendered Sentiment panel (collapsed, under Situations), a section in `now.md`, `api/v1/sentiment.json`, and a methodology section listing every theme counted.

**Open decision for Dan:** whether to add a monthly public-concern reading from published polls (Claude-maintained, with sources), accepting the extra run cost and that the figures would be cited rather than redistributed.

## 17. v1.3 — bias review and first fixes (2 Nov 2026)

Dan asked what the project's blind spots were, and whether his early prompts had biased or narrowed it. The review found four sources of bias. The **brief** named five areas, which became the high weights, and finance dominated (28 of 89 signals in markets, economy and energy against 4 humanitarian). **Recency**: v1.1 additions followed that week's news and thresholds were set while looking at current values. The **format**: a 4×-daily traffic light suits fast risks and fits slow ones badly. The **assessor**: thin, concentrated, mostly English-language sourcing, and a success criterion that measured agreement with Dan. Dan asked to start addressing them.

**Decisions (Dan, 2 Nov 2026):**

- **World State index, method 2:** equal domain weights (all 1.0), and signals in the same situation count once within each domain. Situations therefore now affect the index, so CLAUDE.md rule 13 limits membership to signals whose current level the event mainly explains. On the statuses at the time the score moved from 42 to 40. The method 1 series is archived in `site/data/world_v1.json` and the trend line restarts.
- **Ship straight to `main`.**

**Changes made:**

- **Basis on every status:** `measured` (metric floor decides, computed by `apply`), `published` (a named body's figure, declared by the assessor and checked against the catalogue's new `published` field on 28 signals), or `judged`. Judged statuses carry an AI badge on the board, the legend counts them, the detail panel and `/s/{id}` explain how each status was set, and every agent output carries `basis` (`provenance` is deprecated). At the first build: 25 measured, 15 published and 49 judged. Statuses assessed before this have a reconstructed basis until their next check.
- **Sourcing rules** enforced by `apply`: a judged Alert needs two independent outlets, one trusted; an `avoid` list (encyclopedias, self-publishing, social media, forums) is rejected; no news outlet may exceed 20% of a run's news citations (warning above 10%; official bodies and data feeds exempt). Twelve established outlets added to the trusted list. `runs.json` now records basis counts and the top outlets per run.
- **Catalogue governance:** `signals/catalogue.lock.json` (v1.3) fingerprints ids, domains, weights, tiers, horizons, metrics, rubrics and `published`. `check` fails on any unlocked change, and `canary.py lock` records approved changes in `signals/CHANGELOG.md`. The catalogue is **frozen until 2 Dec 2026**, with written inclusion, graduation (emerging for 14+ days) and review rules (Normal for 90 days); `plan` lists candidates for Dan's weekly review.
- **Coverage map:** `signals/coverage.yaml` maps the catalogue against WEF's Global Risks Report 2026 (33 risks): 12 covered, 12 partial, 9 gaps (frontier technologies, censorship and surveillance, crime, human rights, inequality, misinformation, online harms, pollution, labour shortages). It is rendered on the methodology page, gaps first.
- **Methodology:** new sections on how each status is set, known limitations and biases, coverage and gaps, and how the catalogue changes. Index and situations text corrected. `llms.txt` and `now.md` point agents to the limitations.

**Not yet done (next steps, in order):**

1. Backtest the metric rubrics against 2008, 2020 and 2022 with FRED and other open series, and record the results before the freeze ends.
2. Run the day-30 external agreement check (§10) around 30 Nov.
3. Design a slow-risk panel (monthly, no traffic light) for structural gaps such as inequality, biodiversity, low-income debt distress and antimicrobial resistance.
4. Deliberate regional and non-English sourcing: add regional outlets to the trusted list and the catalogue `hints`.
5. After the freeze: decide which coverage gaps deserve signals, using the inclusion rules.

