---
name: canary-update
description: Run a Canary assessment — refresh metrics, research every due signal, group situations, apply rubric-based RAG statuses with sources, validate, and push. Use for the scheduled 4×-daily run or whenever asked to "update Canary" or "refresh the board".
---

# Canary update run

The goal is to re-assess every signal that is due, using the rubrics in `signals/catalogue.yaml`, and publish the result. The site redeploys automatically on push. **A run that fails validation must not be pushed.** The site then keeps the last good state.

Read `CLAUDE.md` first if it isn't already in context. Its editorial rules apply to every word you write.

## 0. Setup (≈1 min)

```bash
cd <repo root>
git pull --rebase
pip install -r requirements.txt --quiet 2>/dev/null || pip install -r requirements.txt --break-system-packages --quiet
python scripts/fetch_metrics.py          # refresh hard numbers (safe to re-run)
python scripts/canary.py plan > /tmp/plan.txt; cat /tmp/plan.txt
```

The plan lists every **due** signal:
- `fast` signals are always due.
- `daily` signals are due once they're more than 20h old.

For each due signal the plan shows its previous status and value. Metric-backed signals also show a **metric floor**: the status the numeric rubric implies, with hysteresis already applied.

The plan also prints **context anchors** (the daily Geopolitical Risk and Economic Policy Uncertainty indices, ECB systemic stress, EU gas storage when configured). They inform judgement on qualitative signals; they never set a status on their own.

Signals marked `prev=—` have **never been assessed**. Give them a full first assessment; the one-step rule doesn't apply to a first rating.

## 1. Research (the main work)

Work through the plan **domain by domain**. For each due signal:

1. **Metric-backed signals** (those with a metric floor):
   - Accept the floor status unless you find qualitative evidence that pushes it *higher*. Examples: a bank failure for `banking-stress`, an NHC landfall forecast for `atlantic-cyclones`.
   - Write context from the metrics plus at most one search for "why is X moving".
   - The metric's own source URL (from `site/data/metrics.json`) counts as a source.
2. **Qualitative signals:** run **1–2 WebSearch queries**, targeted at the last 72 hours, e.g. `"Sudan RSF El Fasher" news October 2026`. Use the catalogue `hints` for which outlets to trust. Open a page with WebFetch only if the snippets don't settle the status.
3. Decide the status strictly against the rubric. **Compare with the previous status:** change it only if the evidence clearly crosses a rubric line (hysteresis). If nothing material happened, keep the status, set `trend: "flat"` and refresh `state` with the latest dated fact.
4. **Set the trend.** It describes the direction of risk:
   - `up` = worsening over roughly the past week
   - `flat` = stable
   - `down` = easing

5. **Surprise check (once per run, 1–2 searches).** Look for anything significant that no signal covers: scan the latest International Crisis Group CrisisWatch and the top world news of the last 24 hours. If something would rate Watch or higher and fits no catalogue signal, add it to `run.emerging` (max 3, with sources). If an existing emerging item is still live, carry it forward with fresh sources; drop it when it fades or a signal now covers it.

**Budget:** aim for at most ~100 searches per full run (89 signals).
- Batch independent searches in parallel. Send several WebSearch calls in one turn, one per signal in the same domain.
- Don't search for a qualitative signal if a search for a neighbouring signal already covered it. For example, one Middle East search often informs `middle-east`, `iran-nuclear` and `chokepoints`.
- If the Agent tool is available and the run is large, you may hand 2–3 domains each to subagents. Pass each one the plan lines, the catalogue entries and these instructions, and have it return JSON in the update format below.

## 2. Write the updates file

Create `work/updates.json` (the folder is git-ignored) like this:

```json
{
  "run": {
    "headline": "One or two sentences on what matters most right now across the board (≤ 260 chars). Neutral tone.",
    "note": "optional: anything odd about this run (failed sources, judgement calls)"
  },
  "signals": [
    {
      "id": "oil",
      "status": "red",
      "trend": "up",
      "value": "$113.4 · 1m +11%",
      "value_num": 113.4,
      "summary": "Brent above $110 as Gulf supply disruption persists",
      "state": "Brent settled at $113 on 30 Oct, above the $110 Alert threshold for a third week… (2–4 sentences, dated facts)",
      "for_you": "Expect higher fuel and transport costs to feed through over coming weeks. (descriptive for finance; official guidance links for safety topics)",
      "rubric_hit": "Brent $113 > $110 Alert line",
      "sources": [{"title": "Reuters — Oil prices …", "url": "https://…", "date": "2026-10-30"}]
    }
  ]
}
```

`run` may also carry the two cross-signal layers. Each **replaces** the previous list when present; omit the key to keep the previous one unchanged.

```json
"run": {
  "headline": "…",
  "situations": [
    {"id": "us-iran-war", "name": "US–Iran war and Gulf energy shock", "status": "red", "trend": "up",
     "summary": "≤ 160 chars, dated facts", "signals": ["gulf-iran", "oil", "eu-gas", "chokepoints"]}
  ],
  "emerging": [
    {"name": "≤ 60 chars", "status": "amber", "summary": "≤ 160 chars",
     "sources": [{"title": "…", "url": "https://…", "date": "2026-11-01"}], "first_seen": "2026-11-01"}
  ]
}
```

- **Situations:** send the full list every run (3–10 items). A situation groups two or more signals driven by the same event, or one Alert that is a discrete named event (a cyclone, an outbreak). Keep ids stable from run to run. Its status is the highest status among its signals unless you explain otherwise in the summary. Copy the previous list from `site/data/status.json` and edit it.
- **Emerging:** only Watch or Alert (`amber`/`red`) situations that no signal covers, each with 1–3 sources. Send `"emerging": []` to clear the list.

- Include **every due signal**. Omitted signals keep their old `checked_at` and will go ⚪ stale on the site.
- `value` (≤ 48 chars) is shown in its own column on the board, so **give one for every signal**. Metric signals may omit it (the metric's display string is used). Qualitative signals need a short state descriptor, for example `Hormuz 2–8 transits/day`, `Threat level: Severe`, `10,274 cases (29 Oct)`, `No PHEIC since May`.
- `value_num` is optional, but give it when the signal has a natural number. It drives sparklines for non-metric signals.
- `override_reason` (string) is needed only to go below a metric floor or to jump green↔red. Use it sparingly and explain it.

## 3. Apply, validate, review

```bash
python scripts/canary.py apply work/updates.json
```

`apply` first validates the whole file (lengths, sources, advice-like wording, instruction-like text, URLs in prose, situation and emerging structure). **If anything fails, it writes nothing**: fix `work/updates.json` and run `apply` again.

It then:
- merges the updates
- enforces the metric floor and the one-step rule (it prints `WARN` lines when it adjusts something)
- logs status changes
- appends history
- recomputes the World State index
- rebuilds the public outputs (pre-rendered pages, `now.md`, `s/*`, `api/v1/*`, `llms.txt`, `feed.xml`)
- runs `check`

**If `check` reports errors, fix `work/updates.json`** (too long, missing a source, advice-like wording, instruction-like text) and **re-run apply**. Re-applying in the same run is fine. Read the untrusted-source warning: replace weak sources with established ones where you can. Read every `WARN` line. If the floor or the clamp changed a status, make sure `state` still matches the final status. If it doesn't, fix the text and re-apply.

## 4. Commit and push

```bash
git add site/ && git commit -m "update: $(date -u +%Y-%m-%dT%H:%MZ) — <n> changes" && git pull --rebase && git push
```

If the push fails because of a conflict on `site/data/metrics.json` or `site/data/sentiment.json` (both written by the metrics workflow), keep the newer file: `git checkout --theirs site/data/metrics.json site/data/sentiment.json && git add … && git rebase --continue`.

Never edit `site/data/sentiment.json` or use the Sentiment panel as evidence for a status: it is measured by a script, and it is context, not an attention level.

## 5. Report

End with a short summary, under 8 lines:
- signals assessed
- status changes (`id: from→to`)
- any WARNs or failed sources
- the World State score

If the run could not complete, say exactly which step failed. Do not push partial or invalid data.

## Quality bar (spot-check before applying)

- [ ] Every `state` mentions at least one dated fact from the last ~7 days (or says the signal is quiet as of a date).
- [ ] No finance copy reads as advice. Finance `for_you` describes exposure, never actions.
- [ ] Conflict and politics copy is neutral, with casualty figures attributed.
- [ ] Each source URL is a real page you saw this run.
- [ ] Each status matches its rubric. A chronic situation is not an Alert unless the rubric says so.
- [ ] Every Alert sits in a situation or is genuinely standalone; situation summaries carry dated facts.
- [ ] Open `site/now.md`: it should read as a correct one-minute briefing (about 1,000 tokens).
