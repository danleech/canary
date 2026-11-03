---
name: canary-update
description: Run a Canary assessment — refresh metrics, let prep hold unchanged measured signals, research what the brief flags, group situations, apply rubric-based RAG statuses with sources, validate, and push. Use for the scheduled 4×-daily run or whenever asked to "update Canary" or "refresh the board".
---

# Canary update run

The goal is to re-assess every signal that is due, using the rubrics in `signals/catalogue.yaml`, and publish the result, spending research only where something may have changed. The site redeploys automatically on push. **A run that fails validation must not be pushed.** The site then keeps the last good state.

Read `CLAUDE.md` first if it isn't already in context. Its editorial rules apply to every word you write.

## 0. Setup (≈1 min)

```bash
cd <repo root>
git pull --rebase
pip install -r requirements.txt --quiet 2>/dev/null || pip install -r requirements.txt --break-system-packages --quiet
python scripts/fetch_metrics.py          # refresh hard numbers (safe to re-run)
python scripts/canary.py prep            # holds + brief + pre-filled updates file
cat work/brief.md
```

**Read `work/brief.md` and work from it. Don't open `signals/catalogue.yaml` or `site/data/status.json`:** the brief already carries each flagged signal's rubric, hints, previous status, summary and state.

What `prep` does:
- Works out which signals are **due** (`fast` signals always; `daily` signals once they're more than 20h old).
- **Holds measured signals whose data leaves their status unchanged.** It writes a hold entry for each into `work/updates.json`. `apply` refreshes their value, rubric line and check time, and keeps the last text and sources (allowed for 24h after the text was written). You don't research these.
- Lists everything else under **To assess**, with the reason for any flag (the metric floor moved, a status raised above its data floor, text too old, sources that no longer meet the rules, never assessed).
- Pre-fills `run.situations` with the previous list for you to edit.
- In the **05:40 run (full sweep)** it holds nothing, so every due signal's text is rewritten at least once a day. Run `prep --full` to force this at other times.

The brief also carries a **governance** line (catalogue version and freeze, plus emerging risks or quiet signals due for Dan's review; these are for Dan, so never add, remove or re-rubric signals in a run) and **context anchors** (Geopolitical Risk, policy uncertainty, ECB systemic stress). Anchors inform judgement; they never set a status on their own.

A signal shown as **not yet assessed** needs a full first assessment; the one-step rule doesn't apply to a first rating.

If `fetch_metrics.py` ran after `prep`, re-run `prep --force` so the holds use the latest numbers (`--force` rebuilds `work/updates.json`, so do it before adding your own entries).

## 1. Research (the main work)

Work through the brief's **To assess** list **domain by domain**. For each signal:

1. **Metric-backed signals in the list** (flagged because the floor moved, the status sits above its floor, the text is old, or it's the full sweep):
   - Accept the floor status unless you find qualitative evidence that pushes it *higher*. Examples: a bank failure for `banking-stress`, an NHC landfall forecast for `atlantic-cyclones`.
   - Write context from the metrics. Search "why is X moving" (once) only when the status is changing; otherwise the numbers are the story.
   - The metric's own source URL (from `site/data/metrics.json`) counts as a source.
   - Leave prep's holds alone, unless a search for another signal turns up an event that should raise a held signal's status: then replace its hold with a full update.
2. **Qualitative signals:** run **1–2 WebSearch queries**, targeted at the last 72 hours, e.g. `"Sudan RSF El Fasher" news October 2026`. Use the catalogue `hints` for which outlets to trust. Open a page with WebFetch only if the snippets don't settle the status.
   - **Signals with a `published` body** (MI5, IPC, WHO, FAO, Ofgem, Drewry…): go to that body's figure first. If it sets the status, cite it from one of the catalogue's `published.domains` and add `"basis": "published"`.
   - **Sourcing rules (`apply` enforces them):**
     - A judged Alert needs two independent outlets, one on the trusted list. If you can't corroborate it, rate Watch and say the Alert is unconfirmed.
     - Never cite Wikipedia, Substack, social media, forums or blogs (the avoid list). Find the original reporting or the official body.
     - Spread citations: no news outlet may supply more than 20% of the run's news citations. When the same outlet keeps coming up, look for a wire (Reuters, AP, AFP), a national outlet or a regional or non-English source instead. For a conflict, a regional outlet often reports first.
3. Decide the status strictly against the rubric. **Compare with the previous status:** change it only if the evidence clearly crosses a rubric line (hysteresis).
   - **Nothing new since the text was written?** If the brief says *hold allowed: yes* and your search found nothing material after that time, send `{"id": "…", "hold": true}` (optionally with a fresh `value`/`value_num`) instead of rewriting the text. That keeps the previous text and sources for up to 24h after they were written.
   - Otherwise write a full update: keep the status if nothing crossed a line, set `trend: "flat"` and refresh `state` with the latest dated fact.
   - Never hold a signal whose status or trend you're changing, and never hold one the brief says can't be held: `apply` rejects those.
4. **Set the trend.** It describes the direction of risk:
   - `up` = worsening over roughly the past week
   - `flat` = stable
   - `down` = easing

5. **Surprise check (once per run, 1–2 searches).** Look for anything significant that no signal covers: scan the latest International Crisis Group CrisisWatch and the top world news of the last 24 hours. If something would rate Watch or higher and fits no catalogue signal, add it to `run.emerging` (max 3, with sources). If an existing emerging item is still live, carry it forward with fresh sources; drop it when it fades or a signal now covers it.

**Budget:** about one search per signal you assess, plus the surprise check. With prep's holds a normal run needs roughly 20–30 searches; the 05:40 full sweep up to ~60.
- Batch independent searches in parallel. Send several WebSearch calls in one turn, one per signal in the same domain.
- Don't search for a qualitative signal if a search for a neighbouring signal already covered it. For example, one Middle East search often informs `middle-east`, `iran-nuclear` and `chokepoints`.
- If the Agent tool is available and the run is large, you may hand 2–3 domains each to subagents. Pass each one its domains' sections of `work/brief.md` and these instructions, and have it return JSON in the update format below.

## 2. Write the updates file

`prep` has already created `work/updates.json` (the folder is git-ignored) with its holds in `signals` and the previous situations in `run`. **Add** your entries to `signals` and write `run.headline`; don't delete prep's holds. Full entries look like this:

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
    },
    {
      "id": "uk-threat-level",
      "basis": "published",
      "status": "red", "trend": "flat", "value": "Threat level: Severe",
      "summary": "UK national threat level Severe: an attack is highly likely",
      "state": "MI5 has held the national threat level at Severe since <date>… (dated facts)",
      "for_you": "Follow MI5 and police guidance on staying alert in crowded places.",
      "rubric_hit": "MI5 level Severe = Alert",
      "sources": [{"title": "MI5 — Threat levels", "url": "https://www.mi5.gov.uk/threat-levels", "date": "2026-11-02"}]
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

- **Situations:** send the full list every run (3–10 items). Situations change the World State index (signals in one situation count once per domain), so list a signal only when that event is the main reason for its current level. A situation groups two or more signals driven by the same event, or one Alert that is a discrete named event (a cyclone, an outbreak). Keep ids stable from run to run. Its status is the highest status among its signals unless you explain otherwise in the summary. Copy the previous list from `site/data/status.json` and edit it.
- **Emerging:** only Watch or Alert (`amber`/`red`) situations that no signal covers, each with 1–3 sources. Send `"emerging": []` to clear the list.

- Include **every signal the brief lists**, as a full update or a hold. Omitted signals keep their old `checked_at` and will go ⚪ stale on the site.
- A **hold** is just `{"id": "…", "hold": true}`, optionally with `value`, `value_num` and `rubric_hit`. Anything else in it (summary, state, sources, status, trend) is rejected.
- `value` (≤ 48 chars) is shown in its own column on the board, so **give one for every signal**. Metric signals may omit it (the metric's display string is used). Qualitative signals need a short state descriptor, for example `Hormuz 2–8 transits/day`, `Threat level: Severe`, `10,274 cases (29 Oct)`, `No PHEIC since May`.
- `value_num` is optional, but give it when the signal has a natural number. It drives sparklines for non-metric signals.
- `override_reason` (string) is needed only to go below a metric floor or to jump green↔red. Use it sparingly and explain it.
- `basis` (optional): `"published"` only when the signal has a catalogue `published` body, that body's figure set the status, and you cite it from one of its domains. Otherwise omit it. `apply` records `measured` itself when the metric floor decides the status, and `judged` for everything else. The board marks judged statuses with an AI badge.

## 3. Apply, validate, review

```bash
python scripts/canary.py apply work/updates.json
```

`apply` first validates the whole file: lengths, sources, advice-like wording, instruction-like text, URLs in prose, situation and emerging structure, `basis`, avoid-list domains, two outlets per judged Alert and the 20% outlet cap. **If anything fails, it writes nothing**: fix `work/updates.json` and run `apply` again.

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
- signals assessed, and how many were held
- status changes (`id: from→to`)
- basis counts and the top news outlet's share (`apply` prints both)
- any WARNs or failed sources
- the World State score

If the run could not complete, say exactly which step failed. Do not push partial or invalid data.

## Quality bar (spot-check before applying)

- [ ] Every `state` mentions at least one dated fact from the last ~7 days (or says the signal is quiet as of a date).
- [ ] No finance copy reads as advice. Finance `for_you` describes exposure, never actions.
- [ ] Conflict and politics copy is neutral, with casualty figures attributed.
- [ ] Each source URL is a real page you saw this run.
- [ ] Every judged Alert has two independent outlets. Every `basis: "published"` cites that body's own site.
- [ ] Citations are spread across outlets, with regional sources for regional events.
- [ ] Each status matches its rubric. A chronic situation is not an Alert unless the rubric says so.
- [ ] Every Alert sits in a situation or is genuinely standalone; situation summaries carry dated facts.
- [ ] Open `site/now.md`: it should read as a correct one-minute briefing (about 1,000 tokens).
