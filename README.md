# Canary

**The state of the world, checked four times a day.**

Canary is a public, single-page status board. It rates about 70 global risk signals as **Normal**, **Watch** or **Alert**. The signals cover markets, the economy, energy, geopolitics, armed conflict, weather and hazards, climate, global health, technology and cyber, humanitarian crises and the UK.

- Every signal carries a short explanation and sources.
- A scheduled cloud Claude session re-assesses the board against published rubrics.
- The site is static HTML/CSS/JS, hosted on Cloudflare Pages.

See [`CHARTER.md`](CHARTER.md) for the scope and design decisions, and [`site/methodology.html`](site/methodology.html) for the public explanation.

## How it works

```
 GitHub Action (05:10/11:10/17:10/23:10 UTC)   Scheduled Claude task (≈05:40/11:40/17:40/23:40 UK)
   scripts/fetch_metrics.py                       .claude/skills/canary-update
   → site/data/metrics.json ──────────────┐       1. fetch metrics, plan run
                                          ├──►    2. research due signals (web)
                                          │       3. write work/updates.json
                                          │       4. scripts/canary.py apply  (floors, one-step rule, history, feed, validation)
                                          │       5. commit + push
                                          ▼
                              GitHub main ──► Cloudflare Pages auto-deploys site/
```

| Path | Purpose |
|---|---|
| `signals/catalogue.yaml` | Every signal: copy, tier, metrics and the green/amber/red rubric. **This is where you tune Canary.** |
| `scripts/fetch_metrics.py` | Open-data fetchers: Yahoo Finance, FRED, USGS, GDACS, NOAA, NSIDC, ERA5 and the Met Office. No API keys needed. |
| `scripts/canary.py` | `plan` / `apply` / `build` / `check` |
| `site/` | The website. `site/data/*.json` is the whole "database". |
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
5. Update `SITE_URL` in `scripts/canary.py`. It's used for feed links.
6. Later, add a custom domain under **Custom domains**.

### 3. Connect GitHub to Claude

In claude.ai, go to **Settings → Connectors** and connect GitHub with access to the `canary` repo. The scheduled task needs this to push.

### 4. Scheduled task

Ask Claude in this project to "set up the Canary scheduled task", or create one with:

- **Schedule:** `CRON_TZ=Europe/London 40 5,11,17,23 * * *`
- **Prompt:**

  > In the `<you>/canary` repository, run the `canary-update` skill (`.claude/skills/canary-update/SKILL.md`) end to end, following `CLAUDE.md`. Refresh metrics, research every due signal, apply with `scripts/canary.py apply`, and fix any validation errors. Commit and push to `main` only if `check` passes. Finish with a short summary of status changes and any warnings.

## Day-to-day

| I want to… | Do this |
|---|---|
| Run an update now | Ask Claude: "Run the Canary update". You can also trigger the scheduled task manually. |
| Change a threshold | Edit the rubric in `signals/catalogue.yaml`. If it's numeric, also update `suggest()` in `scripts/canary.py`. Then run `python scripts/canary.py check`. |
| Add a signal | Append it to `catalogue.yaml` with a full rubric. Run `check`. It will show as "Not yet assessed" until the next run. |
| Pause updates | Disable the scheduled task. The site keeps its last state and marks signals stale after 14h (or 36h for daily signals). |
| See what happened | `site/data/runs.json` holds the run log. `site/data/changes.json` and `/feed.xml` hold status changes. |
| Preview locally | `cd site && python3 -m http.server 8000`, then open http://localhost:8000 |

## Guard-rails built in

- **Metric floor:** numeric rubrics set a minimum status. Lowering a status below its floor needs a written `override_reason`.
- **Hysteresis:** to step down, a number must clear the threshold by a 10% margin.
- **One-step rule:** no direct Normal↔Alert jump without a hard trigger or an override.
- **Validation:** `check` rejects any signal that lacks sources or exceeds length limits. It also rejects advice-like wording in the finance, economy, energy and UK domains, so Canary never reads as investment advice.
- **Bad runs:** a failed run publishes nothing, and the site keeps its last good state.

## Costs

- **Hosting** is free on Cloudflare Pages.
- **GitHub Actions** usage is small: well under 100 minutes a month.
- **The four daily Claude runs are the main cost.** Each researches about 30–70 signals with up to roughly 90 searches, using your Claude plan's allowance. To reduce it, move more signals to `tier: daily` or drop a run from the schedule.

## Disclaimer

Canary is assessed by an AI model against published rubrics. It is not financial, medical, legal or safety advice.
