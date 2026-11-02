# Canary

**The state of the world, checked four times a day.**

Canary is a public, single-page status board. It rates about 90 global risk signals as **Normal**, **Watch** or **Alert**. The signals cover markets, the economy, energy, geopolitics, armed conflict, weather and hazards, climate, global health, technology and cyber, humanitarian crises and the UK.

- Every signal carries a short explanation and sources.
- A scheduled cloud Claude session re-assesses the board against published rubrics.
- The site is static HTML/CSS/JS, hosted on Cloudflare Pages.
- It is built to be a cheap first stop for **AI agents**: the state of the world in about 1,000 tokens at [`/now.md`](https://canary.danleech.com/now.md), with detail on demand and an MCP server.

See [`CHARTER.md`](CHARTER.md) for the scope and design decisions, and [`site/methodology.html`](site/methodology.html) for the public explanation.

## How it works

```
 GitHub Action (05:10/11:10/17:10/23:10 UTC)   Scheduled Claude task (≈05:40/11:40/17:40/23:40 UK)
   scripts/fetch_metrics.py                       .claude/skills/canary-update
   → site/data/metrics.json ──────────────┐       1. fetch metrics, plan run
                                          ├──►    2. research due signals (web)
                                          │       3. write work/updates.json
                                          │       4. scripts/canary.py apply  (floors, one-step rule, history, validation)
                                          │          └─ scripts/publish.py: pre-rendered HTML + agent outputs
                                          │       5. commit + push
                                          ▼
                              GitHub main ──► Cloudflare Pages auto-deploys site/ (+ functions/ for /mcp)
```

## For AI agents

| Endpoint | What | Size |
|---|---|---|
| `/now.md` | Brief: situations, every Alert, 24h changes, Watch ids | ~1k tokens |
| `/status.md` | Every signal, one row | ~3k tokens |
| `/s/{id}.md` · `/s/{id}.json` · `/s/{id}` | One signal: state, rubric, sources (the last is the citable HTML page) | ~500 |
| `/api/v1/meta.json` | Run metadata: poll this, refetch only when `as_of` changes | ~350 |
| `/api/v1/status.json` | Full state as JSON (schema at `/api/v1/schema.json`) | ~30k |
| `/llms.txt`, `/openapi.json`, `/feed.xml` | Index, OpenAPI description, Atom feed with a daily digest entry | |
| `/mcp` | MCP server (Streamable HTTP, no auth): `get_world_state`, `get_signal`, `get_changes` | |

`/` and `/s/{id}` also return Markdown when the request sends `Accept: text/markdown`. The live sizes are listed in `llms.txt` and on the methodology page.

Guard-rails for agents reading Canary: every output carries `as_of`, `valid_until` and per-signal `stale_after`; machine outputs use the public vocabulary (`alert`/`watch`/`normal`, `worsening`/`stable`/`improving`, `horizon: acute|seasonal|chronic`) and say how each status was set (`basis: measured|published|judged`); `check` blocks instruction-like text, invisible Unicode and URLs in prose, so poisoned sources can't pass instructions through Canary into other models.

| Path | Purpose |
|---|---|
| `signals/catalogue.yaml` | Every signal: copy, tier, metrics and the green/amber/red rubric. **This is where you tune Canary.** |
| `scripts/fetch_metrics.py` | Open-data fetchers: Yahoo Finance, FRED, ECB, USGS, GDACS, NOAA, NSIDC, ERA5, CISA, the Environment Agency, the Met Office and the EPU/GPR indices. No API keys needed (an optional `AGSI_API_KEY` adds EU gas storage). Restricted sources publish derived values only. |
| `scripts/canary.py` | `plan` / `apply` / `build` / `check` |
| `scripts/publish.py` | Generates the pre-rendered pages and every agent-facing output (run by `build`) |
| `signals/trusted_sources.yaml` | Known-good source domains (others are flagged in the run log), never-cite platforms and official suffixes |
| `signals/coverage.yaml` | The catalogue mapped against WEF's 33 global risks: what's covered, partly covered and missing |
| `signals/catalogue.lock.json`, `signals/CHANGELOG.md` | Catalogue version, freeze date and change history, written by `canary.py lock` |
| `functions/` | Cloudflare Pages Functions: the MCP server and Markdown content negotiation |
| `mcp/server.json` | Listing file for the official MCP Registry |
| `site/` | The website, built on the IBM Carbon Design System. `site/data/*.json` is the whole "database". |
| `design/` | Builds `site/assets/carbon.css` and `site/assets/icons.js` from pinned `@carbon/styles` and `@carbon/icons`. |
| `CLAUDE.md` | Editorial rules every Claude session follows |
| `.claude/skills/canary-update/SKILL.md` | The step-by-step update procedure |

## One-time setup

### 1. GitHub

1. Create an empty **public** repo called `canary`.
2. Push this folder to it:

   ```bash
   cd ~/Developer/Canary
   git remote add origin https://github.com/<you>/canary.git
   git push -u origin main
   ```

3. In the repo, go to **Settings → Actions → General → Workflow permissions** and choose **Read and write**. This lets the metrics job commit.

### 2. Cloudflare Pages (about 5 minutes)

1. Go to dash.cloudflare.com, then **Workers & Pages → Create → Pages → Connect to Git**.
2. Pick the `canary` repo.
3. Set the build options:
   - **Framework preset:** None
   - **Build command:** leave empty
   - **Build output directory:** `site`
4. Click **Save and deploy**. The site appears at `https://<project>.pages.dev`.
5. The site is live at **https://canary.danleech.com** (Cloudflare custom domain: CNAME `canary` → `canary-board.pages.dev`, certificate managed by Cloudflare). `SITE_URL` in `scripts/canary.py` matches it, for the feed links.
6. Later, add a custom domain under **Custom domains**.

### 3. Connect GitHub to Claude

In claude.ai, go to **Settings → Connectors** and connect GitHub with access to the `canary` repo. The scheduled task needs this to push.

### 4. Scheduled task

Ask Claude in this project to "set up the Canary scheduled task", or create one with:

- **Schedule:** `CRON_TZ=Europe/London 40 5,11,17,23 * * *`
- **Prompt:**

  > In the `<you>/canary` repository, run the `canary-update` skill (`.claude/skills/canary-update/SKILL.md`) end to end, following `CLAUDE.md`. Refresh metrics, research every due signal, apply with `scripts/canary.py apply`, and fix any validation errors. Commit and push to `main` only if `check` passes. Finish with a short summary of status changes and any warnings.

### 5. Agent access (one-off checks)

1. **Cloudflare AI crawler settings.** In the Cloudflare dashboard for the `danleech.com` zone, open **AI Crawl Control** and make sure AI search and assistant crawlers are allowed (Cloudflare blocks some by default on new domains). Canary's own `robots.txt` allows everyone and declares `Content-Signal: search=yes, ai-input=yes, ai-train=yes`; change `ai-train` in `scripts/publish.py` if you'd rather opt out of training.
2. **MCP Registry (optional).** Install `mcp-publisher` from the [MCP Registry](https://github.com/modelcontextprotocol/registry), then from `mcp/` run `mcp-publisher login github` and `mcp-publisher publish`. The namespace `io.github.danleech/…` needs the `danleech` GitHub login.
3. **EU gas storage (optional).** Get a free key at agsi.gie.eu and add it as the repository secret `AGSI_API_KEY`.

## Day-to-day

| I want to… | Do this |
|---|---|
| Run an update now | Ask Claude: "Run the Canary update". You can also trigger the scheduled task manually. |
| Change a threshold | The catalogue is frozen until 2 Dec 2026. After that, edit the rubric in `signals/catalogue.yaml` (if it's numeric, also update `suggest()` in `scripts/canary.py`), then run `python scripts/canary.py lock --reason "…"` and `check`. `check` fails on any unlocked change. |
| Add a signal | Check it against the inclusion rules in `CLAUDE.md` and update `signals/coverage.yaml`. Append it to `catalogue.yaml` with a full rubric, then `lock` and `check`. It will show as "Not yet assessed" until the next run. |
| Pause updates | Disable the scheduled task. The site keeps its last state and marks signals stale after 14h (or 36h for daily signals). |
| See what happened | `site/data/runs.json` holds the run log. `site/data/changes.json` and `/feed.xml` hold status changes. |
| Preview locally | `cd site && python3 -m http.server 8000`, then open http://localhost:8000 (use `.html` paths locally; Pages serves them without the extension). `npx wrangler pages dev site` also runs the Functions. |
| Review flagged sources | The run log's "not in trusted_sources" warning lists domains to check. Add good ones to `signals/trusted_sources.yaml`. |
| Promote an emerging risk | `canary.py plan` lists emerging risks carried for 14+ days. Promote one only if it passes the inclusion rules in `CLAUDE.md`, then add it as above. |

## Design system

The UI uses **IBM Carbon** components and patterns:
- the UI shell header
- tiles for the KPIs
- compact data tables with expandable rows for the signals
- status indicators (icon plus label)
- the content switcher and search for filtering
- structured lists for the rubrics
- the g10 theme, with g100 for dark mode

The compiled Carbon CSS and icons are committed, so Cloudflare still needs no build step. To change which Carbon components are included, or to upgrade Carbon:

```bash
cd design && npm install && npm run build   # writes site/assets/carbon.css + icons.js
```

Layout and composition live in `site/assets/app.css`. It uses only Carbon tokens (`--cds-*`).

## Guard-rails built in

- **Metric floor:** numeric rubrics set a minimum status. Lowering a status below its floor needs a written `override_reason`.
- **Hysteresis:** to step down, a number must clear the threshold by a 10% margin.
- **One-step rule:** no direct Normal↔Alert jump without a hard trigger or an override.
- **Validation:** `check` rejects any signal that lacks sources or exceeds length limits. It also rejects advice-like wording in the finance, economy, energy and UK domains, so Canary never reads as investment advice.
- **Bad runs:** a failed run publishes nothing, and the site keeps its last good state.
- **Prompt-injection hygiene:** `apply` rejects instruction-like text, invisible Unicode and URLs in prose before anything is written.
- **Data licences:** `metrics.json` never republishes raw series from restricted sources (Yahoo Finance, ICE BofA, Cboe VIX, the academic EPU/GPR indices); only the latest value and derived statistics.

## Costs

- **Hosting** is free on Cloudflare Pages.
- **GitHub Actions** usage is small: well under 100 minutes a month.
- **The four daily Claude runs are the main cost.** Each researches about 30–70 signals with up to roughly 90 searches, using your Claude plan's allowance. To reduce it, move more signals to `tier: daily` or drop a run from the schedule.

## Disclaimer

Canary is assessed by an AI model against published rubrics. It is not financial, medical, legal or safety advice. Canary's statuses and text are licensed CC BY 4.0; third-party data remains its owners'.
