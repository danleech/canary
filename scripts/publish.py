"""Publish Canary's derived outputs for people, search engines and AI agents.

`canary.py build` calls build() after the status file and World State index are up to
date. Everything here is a pure function of site/data/*.json and signals/catalogue.yaml:
it never researches, and never changes a status.

Outputs, all under site/ (smallest first, so agents can stop early):

  now.md                     L0 brief (~1k tokens): situations, Alerts, 24h changes, Watch ids
  status.md                  L1: every signal, one row
  changes.md                 status changes in the last 7 days
  s/{id}.md | .json | .html  L2: one signal — state, rubric, sources; .html is the citable permalink
  api/v1/meta.json           poll this first; fetch more only when as_of changes
  api/v1/status.json         full public state (public vocabulary: alert/watch/normal)
  api/v1/changes.json, api/v1/catalogue.json, api/v1/schema.json
  llms.txt, openapi.json, robots.txt, sitemap.xml, feed.xml, 404.html
  index.html, methodology.html   regions between <!--pre:NAME--> … <!--/pre:NAME--> are
                                 pre-rendered so the page works without JavaScript
"""
from __future__ import annotations

import hashlib
import html
import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.sax.saxutils import escape as xesc

try:
    from zoneinfo import ZoneInfo

    UK = ZoneInfo("Europe/London")
except Exception:  # noqa: BLE001 — tz database missing; fall back to UTC labels
    UK = timezone.utc

PUBLIC = {"green": "normal", "amber": "watch", "red": "alert"}
LABEL = {"green": "Normal", "amber": "Watch", "red": "Alert", "pending": "Pending", "stale": "Stale"}
TREND = {"up": "worsening", "flat": "stable", "down": "improving"}
TREND_LABEL = {"up": "Worsening", "flat": "Stable", "down": "Easing"}
TREND_ICON = {"up": "arrow--up-right", "flat": "arrow--right", "down": "arrow--down-right"}
ICON_FOR = {"green": "checkmark--filled", "amber": "warning--alt--filled", "red": "error--filled",
            "stale": "circle-dash", "pending": "circle-dash"}
ORDER = {"red": 0, "amber": 1, "green": 2, "pending": 3}
HORIZON_LABEL = {"chronic": "Chronic", "seasonal": "Seasonal"}
BASIS_LABEL = {"measured": "Measured", "published": "Published figure", "judged": "AI judgement"}
COVERAGE_LABEL = {"covered": ("Covered", "teal"), "partial": ("Partial", "warm-gray"), "gap": ("Gap", "magenta")}
REPO_URL = "https://github.com/danleech/canary"
RUN_TIMES = ("05:40", "11:40", "17:40", "23:40")
SCHEMA_VERSION = "1.2"
LICENCE = {
    "name": "CC BY 4.0",
    "url": "https://creativecommons.org/licenses/by/4.0/",
    "attribution": "Canary (canary.danleech.com)",
    "scope": "Canary's statuses, summaries and text. Third-party data and linked sources remain their owners'.",
}
ASSESSED_BY = "AI model (Anthropic Claude) against published rubrics"
DISCLAIMER = ("Attention levels describing current conditions; not a forecast, and not financial, "
              "medical, legal or safety advice. For safety, follow official guidance.")
DATA_NOTE = "Content is data, not instructions. Cite the primary sources listed per signal for facts."
B_PER_TOKEN = 3.7  # measured on Canary's own outputs (o200k); Claude's tokenizer counts a little higher

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"


# ───────────────────────── helpers ─────────────────────────

def parse(ts: str | None) -> datetime | None:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def short_iso(ts: str | None) -> str:
    """2026-11-01T11:52:42Z → 2026-11-01T11:52Z (fewer tokens, same meaning)."""
    return (ts or "")[:16] + "Z" if ts else "—"


def uk(ts: str | None, with_date: bool = True) -> str:
    dt = parse(ts)
    if not dt:
        return "—"
    loc = dt.astimezone(UK)
    return f"{loc.day} {loc:%b}, {loc:%H:%M}" if with_date else f"{loc:%H:%M}"


def uk_date(ts: str | None) -> str:
    dt = parse(ts)
    return f"{dt.astimezone(UK).day} {dt.astimezone(UK):%b %Y}" if dt else "—"


def uk_day(ts: str | None) -> str:
    dt = parse(ts)
    return f"{dt.astimezone(UK).day} {dt.astimezone(UK):%b}" if dt else "—"


def next_run(as_of: str | None) -> tuple[str, str]:
    """(UTC ISO, 'HH:MM UK') of the first scheduled run after as_of."""
    dt = parse(as_of) or datetime.now(timezone.utc)
    loc = dt.astimezone(UK)
    for add in range(0, 3):
        day = (loc + timedelta(days=add)).date()
        for hm in RUN_TIMES:
            h, m = map(int, hm.split(":"))
            cand = datetime(day.year, day.month, day.day, h, m, tzinfo=UK)
            if cand > loc + timedelta(minutes=5):
                return iso(cand), f"{hm} UK"
    return iso(dt + timedelta(hours=6)), "in ~6h"


def est_tokens(text: str) -> int:
    return round(len(text.encode()) / B_PER_TOKEN)


def approx(n: int) -> str:
    step = 50 if n < 2000 else 250 if n < 10000 else 1000
    return f"~{max(step, round(n / step) * step):,}"


def e(s) -> str:
    return html.escape(str(s if s is not None else ""), quote=True)


def write(path: Path, text: str, written: list[str]) -> None:
    """Write only when content changed, to keep git diffs (and Pages deploys) small."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return
    path.write_text(text)
    written.append(str(path.relative_to(ROOT)))


def dump(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n"


def load_icons() -> dict:
    p = SITE / "assets" / "icons.js"
    try:
        m = re.search(r"=\s*(\{.*\})\s*;?\s*$", p.read_text(), re.S)
        return json.loads(m.group(1)) if m else {}
    except (OSError, json.JSONDecodeError):
        return {}


ICONS: dict = {}
VERSIONED = ("assets/carbon.css", "assets/app.css", "assets/icons.js", "app.js")
ASSET_V: dict = {}


def asset_versions() -> dict:
    """Short content hashes, appended as ?v= so browsers refetch an asset as soon as it changes
    (Cloudflare serves static files with a 4-hour browser cache)."""
    out = {}
    for rel in VERSIONED:
        f = SITE / rel
        if f.exists():
            out[rel] = hashlib.sha1(f.read_bytes()).hexdigest()[:8]
    return out


def asset(rel: str) -> str:
    return f"/{rel}?v={ASSET_V[rel]}" if rel in ASSET_V else f"/{rel}"


def version_assets(doc: str) -> str:
    """Rewrite asset references in a hand-maintained page (index.html, methodology.html)."""
    for rel in VERSIONED:
        doc = re.sub(r'((?:src|href)=")/?' + re.escape(rel) + r'(?:\?v=\w+)?"', lambda m: m.group(1) + asset(rel) + '"', doc)
    return doc


def svg(name: str, cls: str = "") -> str:
    i = ICONS.get(name)
    if not i:
        return ""
    c = f' class="{cls}"' if cls else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{i["viewBox"]}" width="16" height="16" '
            f'fill="currentColor"{c} aria-hidden="true" focusable="false">{i["inner"]}</svg>')


def status_icon(st: str) -> str:
    st = st if st in ICON_FOR else "pending"
    return f'<span class="cnry-icon cnry-st--{st}">{svg(ICON_FOR[st])}</span>'


def status_indicator(st: str) -> str:
    return f'<span class="cnry-status">{status_icon(st)}<span class="cnry-status__label">{LABEL[st]}</span></span>'


def trend_cell(t: str | None) -> str:
    t = t if t in TREND else "flat"
    return f'<span class="cnry-trend cnry-trend--{t}">{svg(TREND_ICON[t])}<span>{TREND_LABEL[t]}</span></span>'


def tag(text: str, kind: str = "gray") -> str:
    return f'<span class="cds--tag cds--tag--{kind} cds--tag--sm"><span class="cds--tag__label">{e(text)}</span></span>'


def ai_badge() -> str:
    """Marks a status that is the AI assessor's judgement (mirrors aiBadge() in app.js)."""
    return ('<span class="cnry-ai" title="Status set by AI judgement from news reports">AI'
            '<span class="cds--visually-hidden"> judgement</span></span>')


def basis_sentence(basis: str | None, detail: str | None, by: str | None, n_src: int, n_outlets: int) -> str:
    """Plain-language account of how a status was set. Mirrors basisSentence() in app.js."""
    if basis == "measured":
        inputs = (detail or "").replace("=", " = ").replace("; ", " · ")
        return ("Set by a fixed rule applied to open data" + (f" ({inputs})" if inputs else "")
                + ". Anyone can reproduce it from the public metrics file.")
    if basis == "published":
        return (f"Follows {by or 'an official classification'}, read from the cited source by the AI assessor "
                "and checked against the rubric.")
    extra = {"raised above the data floor on reported events": " The data alone would rate it lower; it was raised on reported events.",
             "set below the data floor by assessor override": " The assessor set it below what the data implies, with a written reason."}.get(detail or "", "")
    return (f"The AI assessor's reading of {n_src} source{'' if n_src == 1 else 's'} from {n_outlets} "
            f"outlet{'' if n_outlets == 1 else 's'} against the rubric.{extra} Check the sources before relying on it.")


def outlets_of(sources: list) -> int:
    hosts = set()
    for x in sources:
        try:
            h = x.get("url", "").split("/")[2].split(":")[0].lower()
        except IndexError:
            continue
        parts = re.sub(r"^www\.", "", h).split(".")
        hosts.add(".".join(parts[-3:]) if len(parts) >= 3 and len(parts[-2]) <= 3 and len(parts[-1]) == 2 else ".".join(parts[-2:]))
    return len(hosts)


def hydrate_icons(doc: str) -> str:
    """Fill empty data-icon elements with their SVG so icons show without JavaScript (idempotent)."""
    return re.sub(r'(<(\w+)\b[^>]*\bdata-icon="([\w-]+)"[^>]*>)(</\2>)',
                  lambda mm: mm.group(1) + svg(mm.group(3)) + mm.group(4), doc)


def fill(doc: str, name: str, content: str) -> str:
    pat = re.compile(rf"(<!--pre:{re.escape(name)}-->).*?(<!--/pre:{re.escape(name)}-->)", re.S)
    if not pat.search(doc):
        raise RuntimeError(f"pre-render marker '{name}' missing")
    return pat.sub(lambda m: m.group(1) + content + m.group(2), doc, count=1)


# ───────────────────────── model ─────────────────────────

class Model:
    """Everything the renderers need, computed once."""

    def __init__(self, site_url, cat, status, changes, history, metrics, stale_h):
        self.url = site_url.rstrip("/")
        self.cat, self.status, self.changes, self.history = cat, status, changes, history
        self.metrics, self.stale_h = metrics, stale_h
        self.sigs = status.get("signals", {})
        self.domains = {d["id"]: d for d in cat["domains"]}
        self.by_id = {s["id"]: s for s in cat["signals"]}
        self.as_of = status.get("generated_at")
        t = parse(self.as_of) or datetime.now(timezone.utc)
        self.valid_until = iso(t + timedelta(hours=stale_h["fast"]))
        self.next_run_iso, self.next_run_uk = next_run(self.as_of)
        self.situations = status.get("situations") or []
        self.emerging = status.get("emerging") or []
        self.sit_for: dict[str, list[str]] = {}
        for s in self.situations:
            for sid in s.get("signals", []):
                self.sit_for.setdefault(sid, []).append(s["id"])
        self.world = status.get("world") or {}
        self.coverage: dict | None = None
        self.lock: dict | None = None
        self.records = [self.record(s) for s in cat["signals"]]
        self.rec = {r["id"]: r for r in self.records}
        cutoff = t - timedelta(hours=24)
        self.changed_24h = [c for c in changes if (parse(c["t"]) or t) >= cutoff]
        week = t - timedelta(days=7)
        self.changes_7d = [c for c in changes if (parse(c["t"]) or t) >= week]

    def st(self, sid: str) -> str:
        return (self.sigs.get(sid) or {}).get("status") or "pending"

    def record(self, s: dict) -> dict:
        cur = self.sigs.get(s["id"]) or {}
        st = cur.get("status") or "pending"
        checked = parse(cur.get("checked_at"))
        mkeys = [k for k in s.get("metrics", []) if k in self.metrics and not self.metrics[k].get("error")]
        rec = {
            "id": s["id"], "name": s["name"], "domain": s["domain"],
            "domain_name": self.domains[s["domain"]]["name"],
            "status": PUBLIC.get(st, "pending"), "trend": TREND.get(cur.get("trend")) if cur else None,
            "horizon": s.get("horizon", "acute"), "tier": s["tier"],
            "value": cur.get("value"), "value_num": cur.get("value_num"),
            "summary": cur.get("summary"), "state": cur.get("state"), "for_you": cur.get("for_you"),
            "rubric_hit": cur.get("rubric_hit") or (s["rubric"].get(st) if st in PUBLIC else None),
            "situations": self.sit_for.get(s["id"], []),
            "basis": cur.get("basis") if cur else None,
            "basis_detail": (cur.get("basis_detail") or None) if cur else None,
            "basis_by": (s.get("published") or {}).get("by") if cur.get("basis") == "published" else None,
            "provenance": "metric" if mkeys else "reporting",
            "checked_at": cur.get("checked_at"), "changed_at": cur.get("changed_at"),
            "stale_after": iso(checked + timedelta(hours=self.stale_h[s["tier"]])) if checked else None,
            "sources": cur.get("sources") or [],
            "url": f"{self.url}/s/{s['id']}",
        }
        if cur.get("override_reason"):
            rec["assessor_note"] = cur["override_reason"]
        return rec

    def counts(self) -> dict:
        c = {"alert": 0, "watch": 0, "normal": 0, "pending": 0}
        for r in self.records:
            c[r["status"]] += 1
        return c

    def basis_counts(self) -> dict:
        c = {"measured": 0, "published": 0, "judged": 0}
        for r in self.records:
            if r["status"] != "pending" and r.get("basis") in c:
                c[r["basis"]] += 1
        return c

    def basis_line(self) -> str:
        b = self.basis_counts()
        return (f"Basis: {b['measured']} measured from open data, {b['published']} follow a published figure, "
                f"{b['judged']} are AI judgements from news reports (weigh these with more caution)")

    def header_lines(self) -> list[str]:
        return [
            f"as_of {short_iso(self.as_of)} · next run ~{self.next_run_uk} · stale after {short_iso(self.valid_until)}"
            f" (36h for daily-tier signals)",
            f"Assessed by an {ASSESSED_BY}; attention levels, not forecasts or advice. {LICENCE['name']} · {self.url}",
            f"{self.basis_line()}. Known limitations: {self.url}/methodology#known-limits",
        ]


# ───────────────────────── markdown for LLMs ─────────────────────────

def sig_line(m: Model, r: dict, with_trend: bool = True) -> str:
    tr = f" {r['trend']}" if with_trend and r.get("trend") else ""
    ai = ", AI-judged" if r.get("basis") == "judged" else ""
    return f"- {r['name']} [{r['id']}]{tr}{ai}: {r.get('summary') or '—'}"


def now_md(m: Model) -> str:
    c = m.counts()
    w = m.world
    out = ["# Canary — world risk status", *m.header_lines(), ""]
    pend = f" · {c['pending']} pending first assessment" if c["pending"] else ""
    out.append(f"World State {w.get('score', '–')}/100 ({w.get('band', '—')}) · {c['alert']} Alert · "
               f"{c['watch']} Watch · {c['normal']} Normal{pend}")
    if m.status.get("headline"):
        out.append(f"Headline: {m.status['headline']}")
    covered = set()
    if m.situations:
        out += ["", f"## Situations ({len(m.situations)} cross-domain events; Alerts below are grouped under them)"]
        for s in m.situations:
            ids = s.get("signals", [])
            covered.update(ids)
            groups: dict[str, list[str]] = {}
            for i in ids:
                groups.setdefault(m.rec[i]["status"] if i in m.rec else "pending", []).append(i)
            tagged = "; ".join(f"{k}: {', '.join(groups[k])}" for k in ("alert", "watch", "normal", "pending") if k in groups)
            out.append(f"- {s['name']} [{LABEL.get(s['status'], s['status']).upper()}, {TREND.get(s.get('trend'), 'stable')}]: "
                       f"{s['summary']} → {tagged}")
    alerts = [r for r in m.records if r["status"] == "alert" and r["id"] not in covered]
    acute = [r for r in alerts if r["horizon"] == "acute"]
    slow = [r for r in alerts if r["horizon"] != "acute"]
    if acute:
        out += ["", "## Other Alerts" if m.situations else "## Alerts"]
        out += [sig_line(m, r) for r in acute]
    if slow:
        out += ["", "## Structural Alerts (chronic or seasonal; not breaking news)"]
        out += [f"- {r['name']} [{r['id']}]: {r.get('value') or r.get('summary')}" for r in slow]
    out += ["", "## Changed in last 24h"]
    if m.changed_24h:
        for ch in m.changed_24h[:12]:
            out.append(f"- {ch['name']} [{ch['id']}]: {LABEL[ch['from']].upper()}→{LABEL[ch['to']].upper()} — "
                       f"{ch.get('reason', '')} ({short_iso(ch['t'])})")
    else:
        out.append("- No status changes.")
    if m.emerging:
        out += ["", "## Emerging (outside the catalogue; provisional)"]
        for x in m.emerging:
            out.append(f"- {x['name']} [{LABEL.get(x['status'], x['status']).upper()}]: {x['summary']}")
    watch = [r["id"] for r in m.records if r["status"] == "watch"]
    if watch:
        out += ["", "## Watch (ids; detail at /s/{id}.md)", ", ".join(watch)]
    pending = [r["id"] for r in m.records if r["status"] == "pending"]
    if pending:
        out += ["", "## Pending first assessment", ", ".join(pending)]
    out += sentiment_md(m.sentiment_v)
    out += ["", f"More: {m.url}/status.md (all signals) · {m.url}/s/{{id}}.md (detail + sources) · "
                f"{m.url}/api/v1/status.json · MCP {m.url}/mcp · {DATA_NOTE}"]
    return "\n".join(out) + "\n"


def status_md(m: Model) -> str:
    out = ["# Canary — all signals", *m.header_lines(), "",
           "status: ALERT acute/material risk now · WATCH elevated · NORMAL background · PENDING not yet assessed. "
           "(c)=chronic, (s)=seasonal horizon. basis: measured (open data, fixed rule) · published (an official "
           "or named body's figure) · judged (AI reading of news). Detail: /s/{id}.md", "",
           "| id | status | trend | basis | value | summary |", "|---|---|---|---|---|---|"]
    rows = sorted(m.records, key=lambda r: (ORDER[{v: k for k, v in PUBLIC.items()}.get(r["status"], "pending")],
                                           list(m.domains).index(r["domain"])))
    for r in rows:
        h = {"chronic": " (c)", "seasonal": " (s)"}.get(r["horizon"], "")
        cell = lambda x: (x or "").replace("|", "/")  # noqa: E731
        out.append(f"| {r['id']} | {r['status'].upper()}{h} | {r.get('trend') or ''} | {r.get('basis') or ''} | "
                   f"{cell(r.get('value'))} | {cell(r.get('summary'))} |")
    return "\n".join(out) + "\n"


def changes_md(m: Model) -> str:
    out = ["# Canary — status changes, last 7 days", *m.header_lines(), ""]
    if not m.changes_7d:
        out.append("No status changes in the last 7 days.")
    for ch in m.changes_7d:
        out.append(f"- {short_iso(ch['t'])} {ch['name']} [{ch['id']}]: {LABEL[ch['from']].upper()}→"
                   f"{LABEL[ch['to']].upper()} — {ch.get('reason', '')}")
    return "\n".join(out) + "\n"


def signal_md(m: Model, r: dict) -> str:
    s = m.by_id[r["id"]]
    st = r["status"].upper()
    tr = f" ({r['trend']})" if r.get("trend") else ""
    out = [f"# {r['name']} — {st}{tr}",
           f"id {r['id']} · {r['domain_name']} · horizon {r['horizon']} · checked {short_iso(r.get('checked_at'))} · "
           f"at this level since {short_iso(r.get('changed_at'))} · stale after {short_iso(r.get('stale_after'))}",
           f"Assessed by an {ASSESSED_BY}; not a forecast or advice · {LICENCE['name']} · {r['url']}", ""]
    if r["status"] == "pending":
        out.append("Not assessed yet; the next scheduled run will rate it.")
    else:
        if r.get("value"):
            out.append(f"Value: {r['value']}")
        if r.get("rubric_hit"):
            out.append(f"Rated on: {r['rubric_hit']}")
        if r.get("basis"):
            out.append(f"Basis: {r['basis']} — " + basis_sentence(r["basis"], r.get("basis_detail"), r.get("basis_by"),
                                                                 len(r["sources"]), outlets_of(r["sources"])))
        for sid in r["situations"]:
            sit = next((x for x in m.situations if x["id"] == sid), None)
            if sit:
                out.append(f"Situation: {sit['name']} [{sid}]")
        out += ["", r.get("summary") or "", "", f"Why it's at this level: {r.get('state') or '—'}", "",
                f"What this means for you: {r.get('for_you') or '—'}"]
        if r.get("assessor_note"):
            out += ["", f"Assessor note: {r['assessor_note']}"]
    out += ["", f"Why it matters: {s['why']}", f"What moves it: {s['drivers']}", "",
            f"Rubric — Alert: {s['rubric']['red']} | Watch: {s['rubric']['amber']} | Normal: {s['rubric']['green']}"]
    if r["sources"]:
        out += ["", "Sources:"]
        out += [f"- {x.get('title', '')} ({x.get('date', '')}) {x.get('url', '')}" for x in r["sources"]]
    return "\n".join(out) + "\n"


# ───────────────────────── JSON API ─────────────────────────

def envelope(m: Model) -> dict:
    return {
        "schema": f"{m.url}/api/v1/schema.json", "version": SCHEMA_VERSION,
        "as_of": m.as_of, "valid_until": m.valid_until, "next_run": m.next_run_iso,
        "assessed_by": ASSESSED_BY, "disclaimer": DISCLAIMER, "note": DATA_NOTE, "licence": LICENCE,
    }


def public_situations(m: Model) -> list[dict]:
    return [{**s, "status": PUBLIC.get(s["status"], s["status"]), "trend": TREND.get(s.get("trend"), "stable")}
            for s in m.situations]


def status_json(m: Model) -> dict:
    w = m.world
    return {**envelope(m),
            "headline": m.status.get("headline"),
            "world": {"score": w.get("score"), "band": w.get("band"), "counts": m.counts(),
                      "by_domain": w.get("by_domain", {}), "method": w.get("method"),
                      "method_url": f"{m.url}/methodology#index"},
            "basis_counts": m.basis_counts(),
            "situations": public_situations(m),
            "emerging": [{**x, "status": PUBLIC.get(x["status"], x["status"])} for x in m.emerging],
            "signals": m.records}


def meta_json(m: Model, sizes: dict) -> dict:
    w = m.world
    return {"as_of": m.as_of, "valid_until": m.valid_until, "next_run": m.next_run_iso,
            "world": {"score": w.get("score"), "band": w.get("band")}, "counts": m.counts(),
            "basis_counts": m.basis_counts(), "catalogue_version": (m.lock or {}).get("version"),
            "changed_24h": sorted({c["id"] for c in m.changed_24h}),
            "endpoints": {k: {"url": f"{m.url}/{k}", "tokens": v} for k, v in sizes.items()},
            "licence": LICENCE["name"], "assessed_by": ASSESSED_BY}


def catalogue_json(m: Model) -> dict:
    return {"version": SCHEMA_VERSION, "domains": m.cat["domains"],
            "signals": [{"id": s["id"], "name": s["name"], "domain": s["domain"], "tier": s["tier"],
                         "horizon": s.get("horizon", "acute"), "metrics": s.get("metrics", []),
                         "why": s["why"], "drivers": s["drivers"],
                         "rubric": {"alert": s["rubric"]["red"], "watch": s["rubric"]["amber"],
                                    "normal": s["rubric"]["green"]}}
                        for s in m.cat["signals"]],
            "licence": LICENCE}


def signal_json(m: Model, r: dict) -> dict:
    s = m.by_id[r["id"]]
    hist = [[p[0], PUBLIC.get({"g": "green", "a": "amber", "r": "red"}.get(p[1], ""), p[1]), p[2]]
            for p in (m.history.get(r["id"]) or [])[-40:]]
    return {**envelope(m), **r, "why": s["why"], "drivers": s["drivers"],
            "rubric": {"alert": s["rubric"]["red"], "watch": s["rubric"]["amber"], "normal": s["rubric"]["green"]},
            "history": hist}


def schema_json(m: Model) -> dict:
    status = {"type": "string", "enum": ["alert", "watch", "normal", "pending"]}
    src = {"type": "object", "required": ["title", "url"],
           "properties": {"title": {"type": "string"}, "url": {"type": "string", "format": "uri"},
                          "date": {"type": "string"}}}
    sig = {"type": "object", "required": ["id", "name", "domain", "status", "horizon", "url"], "properties": {
        "id": {"type": "string", "description": "Stable kebab-case id; never renamed"},
        "name": {"type": "string"}, "domain": {"type": "string"}, "domain_name": {"type": "string"},
        "status": {**status, "description": "Attention level now. Treat as stale after stale_after."},
        "trend": {"type": ["string", "null"], "enum": ["worsening", "stable", "improving", None],
                  "description": "Direction of risk over about a week (not the direction of the number)"},
        "horizon": {"type": "string", "enum": ["acute", "seasonal", "chronic"],
                    "description": "Chronic signals (climate trends) can sit at Alert for years"},
        "tier": {"type": "string", "enum": ["fast", "daily"]},
        "value": {"type": ["string", "null"]}, "value_num": {"type": ["number", "null"]},
        "summary": {"type": ["string", "null"], "maxLength": 120},
        "state": {"type": ["string", "null"], "maxLength": 700},
        "for_you": {"type": ["string", "null"], "maxLength": 320},
        "rubric_hit": {"type": ["string", "null"], "description": "The rubric criterion that set this status"},
        "situations": {"type": "array", "items": {"type": "string"}},
        "basis": {"type": ["string", "null"], "enum": ["measured", "published", "judged", None],
                  "description": "How this status was set. measured: a fixed rule applied to open data (reproducible); "
                                 "published: follows a figure or classification by the body in basis_by; judged: the AI "
                                 "assessor's reading of the sources against the rubric. Weigh judged statuses with more caution."},
        "basis_detail": {"type": ["string", "null"], "description": "Rule inputs (measured) or a note on the judgement"},
        "basis_by": {"type": ["string", "null"], "description": "The publishing body, when basis is published"},
        "provenance": {"type": "string", "enum": ["metric", "reporting"],
                       "description": "Deprecated; use basis. metric: the signal has an open data feed; reporting: it does not"},
        "checked_at": {"type": ["string", "null"], "format": "date-time"},
        "changed_at": {"type": ["string", "null"], "format": "date-time"},
        "stale_after": {"type": ["string", "null"], "format": "date-time"},
        "sources": {"type": "array", "items": src},
        "url": {"type": "string", "format": "uri"},
    }}
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"{m.url}/api/v1/schema.json",
        "title": "Canary status (api/v1/status.json)",
        "type": "object",
        "required": ["version", "as_of", "valid_until", "world", "signals"],
        "properties": {
            "version": {"type": "string"}, "as_of": {"type": "string", "format": "date-time"},
            "valid_until": {"type": "string", "format": "date-time",
                            "description": "If now is later than this, the whole board is stale"},
            "next_run": {"type": "string", "format": "date-time"},
            "headline": {"type": ["string", "null"]},
            "world": {"type": "object", "properties": {
                "score": {"type": ["integer", "null"], "minimum": 0, "maximum": 100},
                "band": {"type": ["string", "null"], "enum": ["Calm", "Unsettled", "Strained", "Severe", None]},
                "counts": {"type": "object"}, "by_domain": {"type": "object"}}},
            "situations": {"type": "array", "items": {"type": "object", "required": ["id", "name", "status", "signals"],
                           "properties": {"id": {"type": "string"}, "name": {"type": "string"}, "status": status,
                                          "trend": {"type": "string"}, "summary": {"type": "string"},
                                          "signals": {"type": "array", "items": {"type": "string"}}}}},
            "emerging": {"type": "array", "items": {"type": "object", "required": ["name", "status", "summary", "sources"],
                         "properties": {"name": {"type": "string"}, "status": status, "summary": {"type": "string"},
                                        "sources": {"type": "array", "items": src}}}},
            "signals": {"type": "array", "items": sig},
        },
    }


def openapi_json(m: Model) -> dict:
    md = {"200": {"description": "Markdown", "content": {"text/markdown": {"schema": {"type": "string"}}}}}
    js = lambda ref=None: {"200": {"description": "JSON", "content": {"application/json": {"schema": (  # noqa: E731
        {"$ref": ref} if ref else {"type": "object"})}}}}
    sid = [{"name": "id", "in": "path", "required": True, "schema": {"type": "string"},
            "description": "Signal id, e.g. oil, russia-ukraine, uk-weather. Listed in /api/v1/catalogue.json."}]
    return {
        "openapi": "3.1.0",
        "info": {"title": "Canary global risk status", "version": SCHEMA_VERSION,
                 "description": f"Static, read-only endpoints. {DISCLAIMER} Licence {LICENCE['name']}. "
                                "Start with /now.md (smallest). Poll /api/v1/meta.json and refetch only when as_of changes.",
                 "license": {"name": LICENCE["name"], "url": LICENCE["url"]}},
        "servers": [{"url": m.url}],
        "paths": {
            "/now.md": {"get": {"operationId": "getBrief", "summary": "Current brief: situations, Alerts, 24h changes (~1k tokens)", "responses": md}},
            "/status.md": {"get": {"operationId": "getAllSignalsTable", "summary": "Every signal, one row each", "responses": md}},
            "/changes.md": {"get": {"operationId": "getRecentChanges", "summary": "Status changes in the last 7 days", "responses": md}},
            "/s/{id}.md": {"get": {"operationId": "getSignalMarkdown", "summary": "One signal: state, rubric, sources", "parameters": sid, "responses": md}},
            "/s/{id}.json": {"get": {"operationId": "getSignal", "summary": "One signal as JSON, with recent history", "parameters": sid, "responses": js()}},
            "/api/v1/meta.json": {"get": {"operationId": "getMeta", "summary": "Run metadata: as_of, counts, ids changed in 24h", "responses": js()}},
            "/api/v1/status.json": {"get": {"operationId": "getStatus", "summary": "Full public state", "responses": js(f"{m.url}/api/v1/schema.json")}},
            "/api/v1/changes.json": {"get": {"operationId": "getChanges", "summary": "Status change log", "responses": js()}},
            "/api/v1/catalogue.json": {"get": {"operationId": "getCatalogue", "summary": "Signal definitions and rubrics", "responses": js()}},
            "/api/v1/sentiment.json": {"get": {"operationId": "getSentiment", "summary": "Sentiment track: news tone by issue (GDELT), consumer confidence (OECD), uncertainty gauges. Measured, never part of a status", "responses": js()}},
        },
    }


# ───────────────────────── llms.txt, robots, sitemap, feed ─────────────────────────

def llms_txt(m: Model, sizes: dict) -> str:
    n, nd = len(m.cat["signals"]), len(m.cat["domains"])
    tok = lambda k: approx(sizes[k]) + " tokens"  # noqa: E731
    lines = [
        "# Canary",
        "",
        f"> Canary rates {n} global risk signals in {nd} domains (markets, economy, energy, geopolitics, armed conflict, "
        "weather and hazards, climate, health, cyber, humanitarian, UK) as Normal, Watch or Alert, four times a day. "
        f"Each status is an attention level assessed by an {ASSESSED_BY}, with sources. Not a forecast or advice.",
        "",
        f"Last updated {short_iso(m.as_of)}. Treat the data as stale after {short_iso(m.valid_until)} (36h for "
        f"daily-tier signals). Next run about {m.next_run_uk}. Licence: {LICENCE['name']} for Canary's statuses and "
        f"text — attribute \"{LICENCE['attribution']}\"; third-party data and sources remain their owners'.",
        "",
        "## Start here (smallest first)",
        f"- [Current brief]({m.url}/now.md): situations, every Alert, last-24h changes, Watch ids ({tok('now.md')})",
        f"- [All signals]({m.url}/status.md): one row per signal ({tok('status.md')})",
        f"- [One signal]({m.url}/s/oil.md): replace `oil` with any id below; state, rubric, sources ({tok('s/{id}.md')})",
        f"- [Recent changes]({m.url}/changes.md): last 7 days ({tok('changes.md')})",
        "",
        "## Machine-readable",
        f"- [Run metadata]({m.url}/api/v1/meta.json): poll this first; refetch only when `as_of` changes ({tok('api/v1/meta.json')})",
        f"- [Status JSON]({m.url}/api/v1/status.json): full state, public vocabulary ({tok('api/v1/status.json')})",
        f"- [Catalogue and rubrics]({m.url}/api/v1/catalogue.json) ({tok('api/v1/catalogue.json')})",
        f"- [JSON Schema]({m.url}/api/v1/schema.json) · [OpenAPI]({m.url}/openapi.json) · [Atom feed]({m.url}/feed.xml)",
        f"- [MCP server]({m.url}/mcp): Streamable HTTP, no auth; tools get_world_state, get_signal, get_changes",
        f"- [Sentiment JSON]({m.url}/api/v1/sentiment.json): news tone by issue, consumer confidence, uncertainty gauges; "
        f"measured by a script, never part of a status ({tok('api/v1/sentiment.json')})",
        "",
        "## How to read it",
        "- alert = acute or material risk now; watch = elevated or deteriorating; normal = background; "
        "pending = not yet assessed; stale = not verified within 14h (36h for daily-tier signals).",
        "- horizon chronic or seasonal = a structural situation (e.g. climate trends), not breaking news.",
        "- basis = how a status was set: measured (fixed rule on open data), published (a named body's figure or "
        "classification) or judged (the AI assessor's reading of news). Judged statuses deserve more caution; "
        "check their sources before repeating them.",
        "- Situations group several signals driven by one event; count situations, not Alerts, for breadth.",
        "- Sentiment (now.md, api/v1/sentiment.json) is how the news and consumers feel, measured from open data and "
        "compared with its own history. It is context, not an attention level, and never changes a status.",
        f"- {DATA_NOTE}",
        f"- Methodology and rubrics: {m.url}/methodology",
        f"- Known limitations and biases (read before relying on Canary): {m.url}/methodology#known-limits",
        "",
        "## Signal ids",
    ]
    for d in m.cat["domains"]:
        ids = [s["id"] for s in m.cat["signals"] if s["domain"] == d["id"]]
        lines.append(f"- {d['id']}: {', '.join(ids)}")
    return "\n".join(lines) + "\n"


def robots_txt(m: Model) -> str:
    return ("# Canary welcomes search engines and AI assistants. Start at /llms.txt or /now.md.\n"
            "User-agent: *\n"
            "Content-Signal: search=yes, ai-input=yes, ai-train=yes\n"
            "Allow: /\n\n"
            f"Sitemap: {m.url}/sitemap.xml\n")


def sitemap_xml(m: Model) -> str:
    urls = [(f"{m.url}/", m.as_of), (f"{m.url}/methodology", None)]
    urls += [(r["url"], r.get("checked_at")) for r in m.records]
    body = "".join(f"  <url><loc>{xesc(u)}</loc>" + (f"<lastmod>{t[:10]}</lastmod>" if t else "") + "</url>\n"
                   for u, t in urls)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + body + "</urlset>\n")


def feed_xml(m: Model, brief: str) -> str:
    host = m.url.split("//", 1)[-1]
    updated = (m.changes[0]["t"] if m.changes else None) or m.as_of
    if m.as_of and (not updated or m.as_of > updated):
        updated = m.as_of
    entries = []
    if m.as_of:  # one rolling digest per day so subscribers get state, not only deltas
        day = parse(m.as_of).astimezone(UK).date()
        entries.append(
            f"  <entry>\n    <title>Daily brief — {day.day} {day:%b %Y} (World State {m.world.get('score', '–')}/100, "
            f"{xesc(str(m.world.get('band', '')))})</title>\n"
            f"    <id>tag:{host},{day.isoformat()}:brief</id>\n    <updated>{m.as_of}</updated>\n"
            f"    <link href=\"{m.url}/now.md\" type=\"text/markdown\"/>\n"
            f"    <content type=\"text\">{xesc(brief)}</content>\n  </entry>")
    for c in m.changes[:60]:
        r = m.rec.get(c["id"], {})
        title = f"{c['name']}: {LABEL[c['from']]} → {LABEL[c['to']]}"
        now_line = ""
        if r and r.get("status") != "pending":
            now_line = f" Now {r['status']}" + (f" ({r['trend']})" if r.get("trend") else "") + \
                       (f", {r['value']}" if r.get("value") else "") + f", checked {short_iso(r.get('checked_at'))}."
        entries.append(
            f"  <entry>\n    <title>{xesc(title)}</title>\n"
            f"    <id>tag:{host},{c['t'][:10]}:{c['id']}:{c['t']}</id>\n"
            f"    <updated>{c['t']}</updated>\n"
            f"    <link href=\"{m.url}/s/{c['id']}\"/>\n"
            f"    <summary>{xesc((c.get('reason') or '') + '.' + now_line)}</summary>\n  </entry>")
    return ("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\">\n"
            "  <title>Canary — status changes</title>\n"
            f"  <subtitle>{xesc(DISCLAIMER)}</subtitle>\n"
            f"  <link href=\"{m.url}/\"/>\n  <link rel=\"self\" href=\"{m.url}/feed.xml\"/>\n"
            f"  <id>{m.url}/</id>\n  <updated>{updated}</updated>\n"
            f"  <rights>{LICENCE['name']} — {LICENCE['attribution']}</rights>\n"
            "  <author><name>Canary</name></author>\n" + "\n".join(entries) + "\n</feed>\n")


# ───────────────────────── HTML ─────────────────────────

THEME_SCRIPT = """<script>try{var t=localStorage.getItem('canary.theme');if(t)document.documentElement.setAttribute('data-theme',t);}catch(e){}</script>"""
TOGGLE_SCRIPT = """<script>
(() => {
  const html = document.documentElement, btn = document.getElementById('theme-toggle');
  const I = window.CARBON_ICONS || {};
  const icon = (n) => I[n] ? `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${I[n].viewBox}" width="16" height="16" aria-hidden="true">${I[n].inner}</svg>` : '';
  const cur = () => html.getAttribute('data-theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  const sync = () => { const d = cur() === 'dark'; btn.innerHTML = icon(d ? 'light' : 'asleep'); btn.setAttribute('aria-label', d ? 'Switch to light theme' : 'Switch to dark theme'); };
  btn.addEventListener('click', () => { const n = cur() === 'dark' ? 'light' : 'dark'; html.setAttribute('data-theme', n); try { localStorage.setItem('canary.theme', n); } catch (e) {} sync(); });
  sync();
})();
</script>"""


def page(m: Model, *, title: str, desc: str, canonical: str, body: str, head: str = "", nav: str = "") -> str:
    cur = lambda k: ' cds--header__menu-item--current" aria-current="page' if nav == k else ""  # noqa: E731
    return f"""<!doctype html>
<html lang="en-GB">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(title)}</title>
<meta name="description" content="{e(desc)}">
<meta name="theme-color" content="#161616">
<link rel="canonical" href="{e(canonical)}">
<meta property="og:title" content="{e(title)}">
<meta property="og:description" content="{e(desc)}">
<meta property="og:url" content="{e(canonical)}">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="alternate" type="application/atom+xml" title="Canary status changes" href="/feed.xml">
{head}<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@300;400;600&family=IBM+Plex+Mono:wght@400&display=swap" rel="stylesheet">
<link rel="stylesheet" href="{asset('assets/carbon.css')}">
<link rel="stylesheet" href="{asset('assets/app.css')}">
{THEME_SCRIPT}
</head>
<body>
<a class="cnry-skip" href="#main">Skip to main content</a>
<header class="cds--header cds--g100" aria-label="Canary">
  <a class="cds--header__name" href="/"><span class="cds--header__name--prefix">Canary</span>&nbsp;Global risk status</a>
  <nav class="cds--header__nav" aria-label="Canary">
    <ul class="cds--header__menu-bar">
      <li><a class="cds--header__menu-item{cur('board')}" href="/"><span class="cds--text-truncate--end">Board</span></a></li>
      <li><a class="cds--header__menu-item{cur('methodology')}" href="/methodology"><span class="cds--text-truncate--end">Methodology</span></a></li>
    </ul>
  </nav>
  <div class="cds--header__global">
    <button class="cds--header__action" id="theme-toggle" type="button" aria-label="Switch theme" title="Switch theme">{svg('asleep')}</button>
    <a class="cds--header__action" href="/feed.xml" aria-label="Status change feed (Atom)" title="Status change feed">{svg('rss')}</a>
  </div>
</header>
<main id="main" class="cnry-main">
  <div class="cnry-wrap">
{body}
  </div>
</main>
<footer class="cnry-footer cds--g100">
  <div class="cnry-wrap">
    <p class="cds--type-body-compact-01">Assessed by an AI model (Anthropic's Claude) against <a class="cds--link cds--link--inline" href="/methodology">published rubrics</a>. Not a forecast, and not financial, medical, legal or safety advice. Canary's text is <a class="cds--link cds--link--inline" href="{LICENCE['url']}">{LICENCE['name']}</a>. <a class="cds--link cds--link--inline" href="/methodology#agents">For AI assistants</a> · <a class="cds--link cds--link--inline" href="https://github.com/danleech/canary">Source</a></p>
  </div>
</footer>
<script src="{asset('assets/icons.js')}"></script>
{TOGGLE_SCRIPT}
</body>
</html>
"""


def rubric_list(s: dict, st: str | None, hit: str | None) -> str:
    rows = "".join(
        f'<div class="cds--structured-list-row{" is-current" if st == k else ""}" role="row">'
        f'<div class="cds--structured-list-td" role="cell"><span class="cnry-rubric-level">{status_icon(k)}{LABEL[k]}</span></div>'
        f'<div class="cds--structured-list-td" role="cell">{e(s["rubric"][k])}</div></div>'
        for k in ("red", "amber", "green"))
    note = (f'<p class="cnry-meta-text cnry-rubric-hit">Rated on: {e(hit)}</p>'
            if hit and hit != s["rubric"].get(st or "") else "")
    return (f'<div class="cnry-detail__block"><h3>How it\'s rated</h3>{note}'
            f'<div class="cds--structured-list cds--structured-list--condensed cds--structured-list--flush" role="table" '
            f'aria-label="Rating criteria"><div class="cds--structured-list-tbody" role="rowgroup">{rows}</div></div></div>')


def basis_block(r: dict) -> str:
    if r.get("basis") not in BASIS_LABEL:
        return ""
    lead = (ai_badge() + " ") if r["basis"] == "judged" else ""
    text = basis_sentence(r["basis"], r.get("basis_detail"), r.get("basis_by"), len(r["sources"]), outlets_of(r["sources"]))
    return (f'<div class="cnry-detail__block cnry-basis"><h3>How this status was set</h3><p>{lead}'
            f'<strong>{BASIS_LABEL[r["basis"]]}.</strong> {e(text)} <a class="cds--link cds--link--sm" '
            f'href="/methodology#basis">About the three bases</a></p></div>')


def signal_html(m: Model, r: dict) -> str:
    s = m.by_id[r["id"]]
    cur = m.sigs.get(r["id"]) or {}
    st = cur.get("status") or "pending"
    dom = m.domains[s["domain"]]
    left, right = [], []
    if cur:
        left.append(f'<div class="cnry-detail__lead">{status_indicator(st)}{trend_cell(cur.get("trend"))}'
                    + (f'<span class="cnry-reading">{e(cur.get("value"))}</span>' if cur.get("value") else "") + "</div>")
        left.append(f'<p class="cnry-detail__summary">{e(cur.get("summary"))}</p>')
        left.append(f'<div class="cnry-detail__block"><h3>Why it\'s at this level</h3><p>{e(cur.get("state"))}</p></div>')
        left.append(f'<div class="cnry-detail__block"><h3>What this means for you</h3><p>{e(cur.get("for_you"))}</p></div>')
        left.append(basis_block(r))
    else:
        left.append(f'<div class="cnry-detail__lead">{status_indicator("pending")}</div>'
                    '<p class="cnry-detail__summary">This signal has not been assessed yet. The next scheduled run will rate it.</p>')
    for sid in r["situations"]:
        sit = next((x for x in m.situations if x["id"] == sid), None)
        if sit:
            left.append(f'<div class="cnry-detail__block"><h3>Part of a wider situation</h3><p>{status_icon(sit["status"])} '
                        f'<strong>{e(sit["name"])}</strong>: {e(sit["summary"])}</p></div>')
    left.append(f'<div class="cnry-detail__block cnry-detail__muted"><h3>Why it matters</h3><p>{e(s["why"])}</p></div>')
    left.append(f'<div class="cnry-detail__block cnry-detail__muted"><h3>What moves it</h3><p>{e(s["drivers"])}</p></div>')
    meta = [tag(dom["name"], "cool-gray"), tag("Checked daily" if s["tier"] == "daily" else "Checked every run")]
    if r["horizon"] in HORIZON_LABEL:
        meta.append(tag(HORIZON_LABEL[r["horizon"]], "warm-gray"))
    if cur:
        meta.append(f'<span class="cnry-meta-text">Checked {uk(cur.get("checked_at"))} UK. At this level since '
                    f'{uk(cur.get("changed_at"))}.</span>')
    left.append(f'<div class="cnry-detail__meta">{"".join(meta)}</div>')
    if cur.get("override_reason"):
        left.append(f'<p class="cnry-meta-text">Assessor note: {e(cur["override_reason"])}</p>')
    hist = (m.history.get(r["id"]) or [])[-60:]
    if len(hist) > 1:
        cells = "".join(f'<i class="{e(p[1])}" title="{e(uk(p[0]))}"></i>' for p in hist)
        right.append(f'<div class="cnry-detail__block"><h3>Status at each of the last {len(hist)} checks</h3>'
                     f'<div class="cnry-hist" role="img" aria-label="Status history">{cells}</div></div>')
    right.append(rubric_list(s, st if cur else None, r.get("rubric_hit")))
    if r["sources"]:
        lis = "".join(
            f'<li><a class="cds--link cds--link--sm" href="{e(x.get("url"))}" rel="noopener nofollow">{e(x.get("title"))}'
            f'<span class="cds--link__icon">{svg("launch")}</span></a>'
            + (f'<span class="cnry-src-date">{e(x.get("date"))}</span>' if x.get("date") else "") + "</li>"
            for x in r["sources"])
        right.append(f'<div class="cnry-detail__block"><h3>Sources</h3><ul class="cnry-sources">{lis}</ul></div>')
    body = f"""    <nav class="cnry-crumbs cds--type-body-compact-01" aria-label="Breadcrumb"><a class="cds--link" href="/">Board</a><span aria-hidden="true"> / </span><a class="cds--link" href="/#domain-{e(dom['id'])}">{e(dom['name'])}</a></nav>
    <section class="cnry-pagehead">
      <div><h1 class="cds--type-productive-heading-04">{e(s['name'])}</h1>
      <p class="cnry-pagehead__meta cds--type-body-compact-01">{e(LABEL[st])} · {e(dom['name'])}</p></div>
      <p class="cnry-pagehead__note cds--type-helper-text-01">Assessed by an AI model against <a class="cds--link cds--link--sm" href="/methodology#r-{e(s['id'])}">this signal's rubric</a>. Describes conditions; not a forecast or advice.</p>
    </section>
    <section class="cds--tile cnry-signal-page" aria-label="{e(s['name'])} details">
      <div class="cnry-detail"><div>{''.join(left)}</div><div>{''.join(right)}</div></div>
    </section>
    <p class="cnry-machine cds--type-helper-text-01">This page as <a class="cds--link cds--link--sm" href="/s/{e(s['id'])}.md">Markdown</a> or <a class="cds--link cds--link--sm" href="/s/{e(s['id'])}.json">JSON</a>.</p>"""
    head = (f'<link rel="alternate" type="text/markdown" href="/s/{e(s["id"])}.md">\n'
            f'<link rel="alternate" type="application/json" href="/s/{e(s["id"])}.json">\n')
    desc = f"{s['name']}: {LABEL[st]}. {cur.get('summary') or s['why']}"
    return page(m, title=f"{s['name']} — {LABEL[st]} · Canary", desc=desc[:300], canonical=r["url"], body=body,
                head=head)


def not_found_html(m: Model) -> str:
    body = """    <section class="cnry-pagehead"><div><h1 class="cds--type-productive-heading-04">Page not found</h1>
      <p class="cnry-pagehead__meta cds--type-body-compact-01">There is nothing at this address.</p></div></section>
    <ul class="cds--list--unordered cnry-404">
      <li class="cds--list__item"><a class="cds--link" href="/">The board</a></li>
      <li class="cds--list__item"><a class="cds--link" href="/methodology">Methodology and rubrics</a></li>
      <li class="cds--list__item"><a class="cds--link" href="/now.md">Plain-text brief</a> and <a class="cds--link" href="/llms.txt">llms.txt</a> for AI assistants</li>
    </ul>"""
    return page(m, title="Page not found · Canary", desc="Page not found.", canonical=f"{m.url}/404", body=body)


# Pre-rendered regions of index.html (app.js replaces most of them on load)

def balance(weights: list[int], cols: int) -> list[list[int]]:
    """Port of layoutBoard() in app.js: contiguous groups balanced by row count."""
    total = sum(weights)
    groups: list[list[int]] = [[] for _ in range(cols)]
    g = acc = 0
    for i, w in enumerate(weights):
        remaining = cols - g - 1
        target = total / cols * (g + 1)
        if g < cols - 1 and acc > 0 and acc + w / 2 > target and len(weights) - i > remaining - 1:
            g += 1
        groups[g].append(i)
        acc += w
    return groups


def board_html(m: Model) -> str:
    fresh = {c["id"] for c in m.changed_24h}
    tables = []
    for d in m.cat["domains"]:
        sigs = [s for s in m.cat["signals"] if s["domain"] == d["id"]]
        n: dict[str, int] = {}
        for s in sigs:
            n[m.st(s["id"])] = n.get(m.st(s["id"]), 0) + 1
        tally = "".join(f'<span class="cnry-tally">{status_icon(k)}{n[k]} {LABEL[k]}</span>'
                        for k in ("red", "amber", "green", "pending") if n.get(k))
        rows = []
        for s in sigs:
            cur = m.sigs.get(s["id"]) or {}
            st = m.st(s["id"])
            changed = (' <span class="cds--tag cds--tag--blue cds--tag--sm cnry-changed"><span class="cds--tag__label">'
                       'Changed</span></span>') if s["id"] in fresh else ""
            reading = e(cur["value"]) if cur.get("value") else '<span class="cnry-none">No reading yet</span>'
            if cur and cur.get("basis") == "judged":
                reading += ai_badge()
            t = cur.get("trend") if cur.get("trend") in TREND else None
            trend = (f'<span class="cnry-trend cnry-trend--{t}" title="Trend: {TREND_LABEL[t]}">{svg(TREND_ICON[t])}'
                     f'<span class="cds--visually-hidden">{TREND_LABEL[t]}</span></span>') if t else ""
            rows.append(
                f'<tr class="cds--parent-row" data-parent-row data-id="{s["id"]}" data-st="{st}" id="{s["id"]}">'
                f'<td class="cds--table-expand w-expand"></td>'
                f'<td class="w-status">{status_icon(st)}<span class="cds--visually-hidden">{LABEL[st]}</span></td>'
                f'<td class="w-signal"><span class="cnry-sig__name"><a class="cnry-sig__link" href="/s/{s["id"]}">{e(s["name"])}</a>'
                f'</span>{changed}<span class="cnry-sig__reading">{reading}</span></td>'
                f'<td class="w-trend">{trend}</td></tr>')
        tables.append((len(sigs) + 3, f"""<div class="cds--data-table-container cnry-domain-table" id="domain-{d['id']}" data-domain="{d['id']}" data-weight="{len(sigs) + 3}">
<div class="cds--data-table-header"><h3 class="cds--data-table-header__title">{e(d['name'])}</h3><p class="cds--data-table-header__description">{tally}</p></div>
<div class="cds--data-table-content"><table class="cds--data-table cds--data-table--sm cnry-dt" aria-label="{e(d['name'])} signals">
<tbody>{''.join(rows)}</tbody></table></div></div>"""))
    groups = balance([w for w, _ in tables], 3)
    return "".join('<div class="cnry-col">' + "".join(tables[i][1] for i in grp) + "</div>" for grp in groups)


def domains_html(m: Model) -> str:
    out = []
    by_dom = m.world.get("by_domain") or {}
    for d in m.cat["domains"]:
        sigs = [s for s in m.cat["signals"] if s["domain"] == d["id"]]
        cells = "".join(f'<span class="cnry-icon cnry-st--{m.st(s["id"])}" title="{e(s["name"])}: {LABEL[m.st(s["id"])]}">'
                        f'{svg(ICON_FOR[m.st(s["id"])])}</span>' for s in sigs)
        n: dict[str, int] = {}
        for s in sigs:
            n[m.st(s["id"])] = n.get(m.st(s["id"]), 0) + 1
        sr = ", ".join(f"{n[k]} {LABEL[k]}" for k in ("red", "amber", "green", "pending") if n.get(k))
        score = by_dom.get(d["id"])
        out.append(f'<li class="cnry-domain"><a href="#domain-{d["id"]}" aria-label="{e(d["name"])}: score '
                   f'{score if score is not None else "not available"}; {e(sr)}"><span class="cnry-domain__name">{e(d["name"])}</span>'
                   f'<span class="cnry-domain__score">{score if score is not None else "–"}<small>/100</small></span>'
                   f'<span class="cnry-cells" aria-hidden="true">{cells}</span></a></li>')
    return "".join(out)


def changes_rows(m: Model) -> str:
    rows = m.changes_7d[:8]
    if not rows:
        return '<tr class="cnry-empty-row"><td colspan="3">No status changes in the last 7 days.</td></tr>'
    return "".join(
        f'<tr><td><span class="cnry-sig">{status_icon(c["to"])}<span class="cnry-sig__name">'
        f'<a class="cnry-sig__link" href="/s/{c["id"]}">{e(c["name"])}</a></span></span></td>'
        f'<td><span class="cnry-change">{LABEL[c["from"]]} → {LABEL[c["to"]]}</span></td>'
        f'<td class="cnry-num cnry-when">{e(uk(c["t"]))}</td></tr>' for c in rows)


def situations_html(m: Model) -> str:
    """Collapsible (closed by default) panel: one row per situation, linked signals sorted by severity."""
    if not m.situations and not m.emerging:
        return ""

    def sig_links(ids):
        known = sorted((i for i in ids if i in m.by_id), key=lambda i: ORDER[m.st(i)])
        return "".join(f'<a class="cnry-sit__sig" href="/s/{i}">{status_icon(m.st(i))}<span>{e(m.by_id[i]["name"])}</span>'
                       f'<span class="cds--visually-hidden"> ({LABEL[m.st(i)]})</span></a>' for i in known)

    def name_cell(x, trend=True):
        st = x["status"] if x["status"] in ICON_FOR else "pending"
        tr = f'<span class="cnry-sit__trend">{trend_cell(x.get("trend"))}</span>' if trend else ""
        return (f'<td class="cnry-sit__name-cell"><span class="cnry-sit__name">{status_icon(st)}'
                f'<span class="cds--visually-hidden">{LABEL[st]}: </span><span>{e(x["name"])}</span></span>{tr}</td>')

    rows = "".join(f'<tr>{name_cell(s)}<td class="cnry-sit__what">{e(s["summary"])}</td>'
                   f'<td class="cnry-sit__sigs">{sig_links(s.get("signals", []))}</td></tr>' for s in m.situations)
    table = ""
    if m.situations:
        table = ('<table class="cds--data-table cds--data-table--sm cnry-sit-table" aria-label="Situations">'
                 '<thead><tr><th scope="col" class="cnry-sit__h-name"><div class="cds--table-header-label">Situation</div></th>'
                 '<th scope="col"><div class="cds--table-header-label">What\'s happening</div></th>'
                 '<th scope="col" class="cnry-sit__h-sigs"><div class="cds--table-header-label">Signals</div></th></tr></thead>'
                 f'<tbody>{rows}</tbody></table>')
    emerging = ""
    if m.emerging:
        er = "".join(
            f'<tr>{name_cell(x, trend=False)}<td class="cnry-sit__what">{e(x["summary"])}</td><td class="cnry-sit__sigs">'
            + "".join(f'<a class="cds--link cds--link--sm" href="{e(src.get("url"))}" rel="noopener nofollow">{e(src.get("title"))}</a>'
                      for src in x.get("sources", [])[:2]) + "</td></tr>"
            for x in m.emerging)
        emerging = ('<h3 class="cnry-sit__subhead">Outside the catalogue</h3>'
                    '<p class="cnry-sit__intro">Provisional: risks no signal covers yet. Reviewed weekly; persistent ones become signals.</p>'
                    '<table class="cds--data-table cds--data-table--sm cnry-sit-table" aria-label="Emerging risks">'
                    '<thead><tr><th scope="col" class="cnry-sit__h-name"><div class="cds--table-header-label">Risk</div></th>'
                    '<th scope="col"><div class="cds--table-header-label">What\'s happening</div></th>'
                    '<th scope="col" class="cnry-sit__h-sigs"><div class="cds--table-header-label">Sources</div></th></tr></thead>'
                    f'<tbody>{er}</tbody></table>')
    alerts_total = sum(1 for r in m.records if r["status"] == "alert")
    covered = {i for s in m.situations for i in s.get("signals", []) if m.st(i) == "red"}
    count = f"{len(m.situations)} events behind {len(covered)} of {alerts_total} Alerts" if m.situations else ""
    if m.emerging:
        count += (" · " if count else "") + f"{len(m.emerging)} outside the catalogue"
    icons = "".join(status_icon(s["status"]) for s in m.situations)
    return f"""<details class="cnry-situations" id="situations">
<summary class="cnry-sit__bar"><span class="cnry-sit__chevron">{svg('chevron--right')}</span><span class="cnry-sit__title">Situations</span><span class="cnry-sit__count">{e(count)}</span><span class="cnry-sit__icons" aria-hidden="true">{icons}</span></summary>
<div class="cnry-sit__body"><p class="cnry-sit__intro">One event often moves several signals. Situations group them so you can see how many separate things are happening; they don't change any signal's status.</p>
{table}{emerging}</div>
</details>"""


# ───────────────────────── sentiment track ─────────────────────────
# Measured by scripts/fetch_sentiment.py (GDELT news tone, OECD consumer confidence) plus the EPU,
# GPR and VIX readings already in metrics.json. Never rated by the model; never changes a status.

MOOD_STALE_DAYS = 3
MOOD_BANDS = {"much-gloomier": 2, "gloomier": 1, "typical": 0, "brighter": -1, "much-brighter": -2}
CONF_BAND = {"above": "above average", "below": "below average", "near": "near average"}


def _lc(name: str) -> str:
    return name[:1].lower() + name[1:]


def _month(period: str | None) -> str:
    try:
        return datetime.strptime(period or "", "%Y-%m").strftime("%b %Y")
    except ValueError:
        return period or "—"


def _day(d: str | None) -> str:
    try:
        x = datetime.strptime(d or "", "%Y-%m-%d")
        return f"{x.day} {x:%b}"
    except ValueError:
        return d or "—"


def _join(xs: list[str]) -> str:
    return xs[0] if len(xs) == 1 else ", ".join(xs[:-1]) + " and " + xs[-1]


def _signed(x: float | None, dp: int = 1) -> str:
    if x is None:
        return "—"
    return ("+" if x > 0 else "−" if x < 0 else "±") + f"{abs(x):.{dp}f}"


def sentiment_view(m: Model) -> dict:
    """One normalised view of the sentiment track for the board, now.md and the JSON API."""
    s = m.sentiment or {}
    media = s.get("summary") or {}
    conf = s.get("confidence") or {}
    view: dict = {"media": None, "confidence": None, "gauges": [], "headline": None, "stale": False}
    if media.get("issues"):
        as_of = parse(media["as_of"] + "T00:00:00Z") if media.get("as_of") else None
        ref = parse(m.as_of) or datetime.now(timezone.utc)
        view["stale"] = bool(as_of and (ref - as_of).days > MOOD_STALE_DAYS)
        by_dom = m.world.get("by_domain") or {}
        issues = []
        for i in media["issues"]:
            issues.append({**{k: i.get(k) for k in ("id", "name", "band", "label", "trend", "gloom_pct", "tone",
                                                       "tone_typical", "share", "share_pct", "share_typical",
                                                       "articles")},
                           "spark": i.get("spark") or [],
                           "domains": [{"id": d, "name": m.domains[d]["name"], "short": m.domains[d].get("short") or m.domains[d]["name"],
                                        "score": by_dom.get(d)}
                                       for d in i.get("domains", []) if d in m.domains]})
        view["media"] = {"as_of": media.get("as_of"), "window_days": media.get("window_days"),
                         "baseline_days": media.get("baseline_days"), "articles": media.get("articles"),
                         "spark_start": media.get("spark_start"),
                         "overall": {k: (media.get("overall") or {}).get(k)
                                     for k in ("band", "label", "trend", "gloom_pct", "tone", "tone_typical")},
                         "overall_spark": (media.get("overall") or {}).get("spark") or [],
                         "issues": issues, "source": media.get("source"), "source_url": media.get("source_url")}
    if conf.get("areas"):
        view["confidence"] = {"areas": conf["areas"], "source": conf.get("source"),
                              "source_url": conf.get("source_url"), "error": conf.get("error")}
    met = m.metrics or {}
    epu, gpr, vix = met.get("epu") or {}, met.get("gpr") or {}, met.get("vix") or {}
    if epu.get("vs_1y_median"):
        view["gauges"].append({"id": "epu", "name": "US policy uncertainty", "ratio": epu["vs_1y_median"],
                               "text": f"{epu['vs_1y_median']:.1f}× its 1-year median", "as_of": epu.get("as_of"),
                               "source": "Economic Policy Uncertainty index (Baker, Bloom & Davis)", "url": epu.get("url")})
    if gpr.get("vs_1y_median"):
        view["gauges"].append({"id": "gpr", "name": "Geopolitical risk in the news", "ratio": gpr["vs_1y_median"],
                               "text": f"{gpr['vs_1y_median']:.1f}× its 1-year median", "as_of": gpr.get("as_of"),
                               "source": "Geopolitical Risk index (Caldara & Iacoviello)", "url": gpr.get("url")})
    if vix.get("pct_1y") is not None:
        view["gauges"].append({"id": "vix", "name": "Market fear (VIX)", "pct_1y": vix["pct_1y"],
                               "text": f"higher than {vix['pct_1y']}% of the past year" if vix["pct_1y"] >= 50
                               else f"lower than {100 - vix['pct_1y']}% of the past year",
                               "as_of": (vix.get("as_of") or "")[:10], "source": vix.get("source"), "url": vix.get("url")})
    view["headline"] = sentiment_headline(view)
    return view


def sentiment_headline(v: dict) -> str | None:
    parts = []
    md = v.get("media")
    if md:
        rated = [i for i in md["issues"] if i.get("band") in MOOD_BANDS]
        gloomy = sorted((i for i in rated if MOOD_BANDS[i["band"]] > 0), key=lambda i: -(i.get("gloom_pct") or 0))
        bright = sorted((i for i in rated if MOOD_BANDS[i["band"]] < 0), key=lambda i: i.get("gloom_pct") or 0)
        if gloomy:
            parts.append("News coverage is gloomier than usual on " + _join([_lc(i["name"]) for i in gloomy]))
        if bright:
            parts.append(("and brighter on " if gloomy else "News coverage is brighter than usual on ")
                         + _join([_lc(i["name"]) for i in bright]))
        if rated and not gloomy and not bright:
            parts.append(f"News tone is within its usual range on all {len(rated)} issues")
        if not rated:
            parts.append("News tone baseline is still building")
    line = " ".join(parts)
    c = v.get("confidence")
    if c and c["areas"]:
        a = c["areas"][0]
        line = (line + ". " if line else "") + (f"{a['name']} consumer confidence is {a['value']:.1f} "
                                                f"({_month(a['period'])}), {CONF_BAND[a['band']]}")
    return (line + ".") if line else None


def mood_spark(vals: list, typical: float | None, label: str, w: int = 120, h: int = 28) -> str:
    pts = [(k, v) for k, v in enumerate(vals) if isinstance(v, (int, float))]
    if len(pts) < 2:
        return ""
    ys = [v for _, v in pts] + ([typical] if typical is not None else [])
    lo, hi = min(ys), max(ys)
    if hi - lo < 0.2:
        mid = (hi + lo) / 2
        lo, hi = mid - 0.1, mid + 0.1
    n = max(1, len(vals) - 1)
    X = lambda k: 2 + k / n * (w - 4)  # noqa: E731
    Y = lambda v: 2 + (1 - (v - lo) / (hi - lo)) * (h - 4)  # noqa: E731
    d = "".join(f"{'L' if j else 'M'}{X(k):.1f} {Y(v):.1f}" for j, (k, v) in enumerate(pts))
    base = (f'<line x1="2" x2="{w - 2}" y1="{Y(typical):.1f}" y2="{Y(typical):.1f}" stroke="var(--cds-border-strong-01)" '
            f'stroke-width="1" stroke-dasharray="2 2"/>') if typical is not None else ""
    lx, ly = X(pts[-1][0]), Y(pts[-1][1])
    return (f'<svg class="cnry-mood__spark" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="{e(label)}">'
            f'{base}<path d="{d}" fill="none" stroke="var(--cds-icon-secondary)" stroke-width="1.25" stroke-linejoin="round"/>'
            f'<circle cx="{lx:.1f}" cy="{ly:.1f}" r="2.5" fill="var(--cds-icon-primary)"/></svg>')


def mood_meter(pct: int | None, band: str | None) -> str:
    if pct is None:
        return ""
    return (f'<span class="cnry-mood__meter" aria-hidden="true" data-band="{e(band or "")}">'
            f'<span class="cnry-mood__mark" style="inset-inline-start: {min(max(pct, 0), 100)}%"></span></span>')


TREND_WORDS = {"gloomier": "getting gloomier", "brighter": "getting brighter"}


def gloom_phrase(pct: int) -> str:
    if pct >= 100:
        return "Gloomier than any week in the past 6 months"
    if pct <= 0:
        return "Brighter than any week in the past 6 months"
    return f"Gloomier than {pct}% of past weeks" if pct >= 50 else f"Brighter than {100 - pct}% of past weeks"


def share_phrase(pct: int) -> str:
    if pct >= 100:
        return "highest in 6 months"
    if pct <= 0:
        return "lowest in 6 months"
    return f"higher than {pct}% of past weeks" if pct >= 50 else f"lower than {100 - pct}% of past weeks"


def sentiment_html(m: Model) -> str:
    v = m.sentiment_v
    md, conf, gauges = v["media"], v["confidence"], v["gauges"]
    if not md and not conf:
        return ""
    rows = []
    if md:
        since = _day(md.get("spark_start"))
        for i in md["issues"]:
            rated = i.get("band") in MOOD_BANDS
            trend = TREND_WORDS.get(i.get("trend") or "")
            label = e(i.get("label") or "—")
            detail = (f"{gloom_phrase(i['gloom_pct'])}{' · ' + trend if trend else ''} · tone "
                      f"{_signed(i['tone'], 2)}, usual {_signed(i['tone_typical'], 2)}"
                      if rated else "Not enough comparable history yet")
            share = (f'<span class="cnry-mood__val"><span class="cnry-mood__k">Coverage </span>{i["share"]:.1f}%</span>'
                     f'<span class="cnry-mood__sub">usual {i["share_typical"]:.1f}% · {share_phrase(i["share_pct"])}</span>'
                     if rated and i.get("share") is not None and i.get("share_typical") is not None else
                     f'<span class="cnry-mood__val">{i["share"]:.1f}%</span>' if i.get("share") is not None else "—")
            spark = mood_spark(i["spark"], i.get("tone_typical"),
                               f"{i['name']}: 7-day news tone each day since {since}; dashed line is the 6-month typical value")
            doms = "".join(f'<a class="cnry-mood__dom" href="#domain-{d["id"]}">{e(d["short"])} '
                           f'<span class="cnry-num">{d["score"] if d["score"] is not None else "–"}</span></a>'
                           for d in i["domains"])
            rows.append(
                f'<tr data-band="{e(i.get("band") or "")}"><th scope="row" class="cnry-mood__issue">{e(i["name"])}</th>'
                f'<td class="cnry-mood__tone">{mood_meter(i.get("gloom_pct") if rated else None, i.get("band"))}'
                f'<span class="cnry-mood__val">{label}</span><span class="cnry-mood__sub">{e(detail)}</span></td>'
                f'<td class="cnry-mood__share">{share}</td>'
                f'<td class="cnry-mood__chart">{spark}</td>'
                f'<td class="cnry-mood__doms">{doms}</td></tr>')
    table = ""
    if md:
        ov = md["overall"]
        ov_line = (f'All coverage: {e(ov.get("label") or "—").lower()}' + (f', gloomier than {ov["gloom_pct"]}% of past weeks'
                   if ov.get("gloom_pct") is not None else "") + ".") if ov.get("label") else ""
        table = (f'<div class="cnry-mood__media"><h3 class="cnry-mood__h">News tone by issue</h3>'
                 f'<p class="cnry-mood__note">{md.get("articles", 0):,} articles in the 7 days to {_day(md["as_of"])}, in English and '
                 f'~65 languages machine-translated by GDELT. Each issue is compared only with its own past 6 months. {ov_line}</p>'
                 '<table class="cds--data-table cds--data-table--sm cnry-mood-table" aria-label="News tone by issue">'
                 '<thead><tr><th scope="col" class="cnry-mood__h-issue"><div class="cds--table-header-label">Issue</div></th>'
                 '<th scope="col" class="cnry-mood__h-tone"><div class="cds--table-header-label">Tone vs usual</div></th>'
                 '<th scope="col" class="cnry-mood__h-share"><div class="cds--table-header-label">Share of coverage</div></th>'
                 '<th scope="col" class="cnry-mood__h-chart"><div class="cds--table-header-label">Tone, 90 days</div></th>'
                 '<th scope="col" class="cnry-mood__h-doms"><div class="cds--table-header-label">Canary score</div></th></tr></thead>'
                 f'<tbody>{"".join(rows)}</tbody></table></div>')
    side = []
    if conf:
        crow = "".join(
            f'<div class="cds--structured-list-row" role="row"><div class="cds--structured-list-td" role="cell">{e(a["name"])}</div>'
            f'<div class="cds--structured-list-td cnry-num" role="cell">{a["value"]:.1f}</div>'
            f'<div class="cds--structured-list-td cnry-num" role="cell">{_signed(a.get("chg_12m"))}</div>'
            f'<div class="cds--structured-list-td cnry-mood__month" role="cell">{_month(a["period"])}</div></div>' for a in conf["areas"])
        head = ('<div class="cds--structured-list-thead" role="rowgroup"><div class="cds--structured-list-row '
                'cds--structured-list-row--header-row" role="row">' + "".join(
                    f'<div class="cds--structured-list-th" role="columnheader">{h}</div>'
                    for h in ("Economy", "Index", "On a year", "Latest")) + "</div></div>")
        side.append('<div class="cnry-mood__block"><h3 class="cnry-mood__h">Consumer confidence</h3>'
                    '<p class="cnry-mood__note">OECD harmonised index from household surveys; 100 is each economy\'s long-run '
                    'average, so below 100 means gloomier than usual. Monthly, published with a lag.</p>'
                    '<div class="cds--structured-list cds--structured-list--condensed cds--structured-list--flush cnry-mood__list" role="table" '
                    f'aria-label="Consumer confidence">{head}<div class="cds--structured-list-tbody" role="rowgroup">{crow}</div></div></div>')
    if gauges:
        grow = "".join(
            f'<div class="cds--structured-list-row" role="row"><div class="cds--structured-list-td" role="cell">{e(g["name"])}</div>'
            f'<div class="cds--structured-list-td" role="cell">{e(g["text"])}</div></div>' for g in gauges)
        side.append('<div class="cnry-mood__block"><h3 class="cnry-mood__h">Uncertainty</h3>'
                    '<p class="cnry-mood__note">Text- and market-based fear gauges, compared with their own past year.</p>'
                    '<div class="cds--structured-list cds--structured-list--condensed cds--structured-list--flush cnry-mood__list" role="table" '
                    f'aria-label="Uncertainty gauges"><div class="cds--structured-list-tbody" role="rowgroup">{grow}</div></div></div>')
    rated = [i for i in (md or {}).get("issues", []) if i.get("band") in MOOD_BANDS]
    gloomy = sum(1 for i in rated if MOOD_BANDS[i["band"]] > 0)
    count_bits = []
    if rated:
        count_bits.append(f"News gloomier than usual on {gloomy} of {len(rated)} issues")
    if conf:
        a = conf["areas"][0]
        count_bits.append(f"{a['name']} consumer confidence {a['value']:.1f}")
    marks = "".join(f'<span class="cnry-mood__dot" data-band="{e(i["band"])}" title="{e(i["name"])}: {e(i["label"])}"></span>'
                    for i in rated)
    stale = (f'<p class="cnry-mood__stale">News tone not updated since {_day(md["as_of"])}; the open-data feed may be down.</p>'
             if v["stale"] and md else "")
    return f"""<details class="cnry-situations cnry-mood" id="sentiment">
<summary class="cnry-sit__bar"><span class="cnry-sit__chevron">{svg('chevron--right')}</span><span class="cnry-sit__title">Sentiment</span><span class="cnry-sit__count">{e(' · '.join(count_bits))}</span><span class="cnry-mood__dots" aria-hidden="true">{marks}</span></summary>
<div class="cnry-sit__body"><p class="cnry-sit__intro">How the news and the public feel about the issues Canary tracks, measured from open data by a script. It is context, not an attention level: it never changes a signal's status or the World State index. {e(v.get('headline') or '')} <a class="cds--link cds--link--sm" href="/methodology#sentiment">How it's measured</a></p>{stale}
<div class="cnry-mood__grid">{table}<div class="cnry-mood__side">{''.join(side)}</div></div></div>
</details>"""


def sentiment_md(v: dict) -> list[str]:
    """Lines for now.md (~100 tokens)."""
    if not v.get("media") and not v.get("confidence"):
        return []
    out = ["", "## Sentiment (measured from open data; context only, never changes a status)"]
    md = v.get("media")
    if md:
        rated = [i for i in md["issues"] if i.get("band") in MOOD_BANDS]
        grp: dict[str, list[str]] = {}
        for i in rated:
            k = "gloomier" if MOOD_BANDS[i["band"]] > 0 else "brighter" if MOOD_BANDS[i["band"]] < 0 else "typical"
            grp.setdefault(k, []).append(f"{i['id']} ({i['gloom_pct']})" if k != "typical" else i["id"])
        bits = "; ".join(f"{k}: {', '.join(grp[k])}" for k in ("gloomier", "brighter", "typical") if k in grp)
        stale = " STALE" if v.get("stale") else ""
        out.append(f"News tone vs own past 6 months (GDELT, 7 days to {md['as_of']}{stale}; number = % of past weeks less "
                   f"negative): {bits or 'baseline building'}")
    c = v.get("confidence")
    if c:
        out.append("Consumer confidence (OECD, long-run avg 100): " + ", ".join(
            f"{a['id']} {a['value']:.1f} ({a['period']})" for a in c["areas"]))
    if v.get("gauges"):
        out.append("Uncertainty: " + " · ".join(f"{g['name']} {g['text']}" for g in v["gauges"]))
    return out


def sentiment_json(m: Model) -> dict:
    v = m.sentiment_v
    note = ("Measured from open data by a script; not assessed by the AI model and never part of a signal's status "
            "or the World State index. News tone is GDELT's lexicon-based score of how coverage is written, not a poll "
            "of what people think.")
    return {**envelope(m), "assessed_by": "script (no AI judgement)", "about": note,
            "headline": v.get("headline"), "stale": v.get("stale"),
            "media": v.get("media"), "confidence": v.get("confidence"), "gauges": v.get("gauges"),
            "bands": {"gloom_pct": "share of 7-day windows in the past 180 days with less negative tone than now",
                      "much-gloomier": ">= 90", "gloomier": "75-89", "typical": "26-74", "brighter": "11-25",
                      "much-brighter": "<= 10"},
            "attribution": ["GDELT Project (https://www.gdeltproject.org/)", "OECD", "Baker, Bloom & Davis (EPU)",
                            "Caldara & Iacoviello (GPR)"]}


def sentiment_method_html(cfg: dict | None) -> str:
    if not cfg:
        return ""
    rows = "".join(
        f'<tr><td><strong>{e(i["name"])}</strong></td><td>{e(", ".join(i.get("domains", [])))}</td>'
        f'<td class="cnry-mood__themes">{e(", ".join(t.replace("*", "…") for t in i["themes"]))}</td></tr>'
        for i in cfg.get("media", {}).get("issues", []))
    return ('<table class="cds--data-table cds--data-table--sm cnry-mood-themes" aria-label="Sentiment issues and GDELT themes">'
            '<thead><tr><th scope="col" style="inline-size:22%"><div class="cds--table-header-label">Issue</div></th>'
            '<th scope="col" style="inline-size:18%"><div class="cds--table-header-label">Canary domains</div></th>'
            '<th scope="col"><div class="cds--table-header-label">GDELT themes counted</div></th></tr></thead>'
            f'<tbody>{rows}</tbody></table>')


def legend_html(m: Model) -> str:
    st = "".join(f'<span class="cnry-legend__item">{status_icon(k)}{LABEL[k]}</span>' for k in ("red", "amber", "green", "stale"))
    tr = "".join(f'<span class="cnry-legend__item cnry-trend cnry-trend--{k}">{svg(TREND_ICON[k])}<span>{TREND_LABEL[k]}</span></span>'
                 for k in ("up", "flat", "down"))
    b = m.basis_counts()
    return (f'<span class="cnry-legend__group"><span class="cnry-legend__title">Status</span>{st}</span>'
            f'<span class="cnry-legend__group"><span class="cnry-legend__title">Trend</span>{tr}</span>'
            f'<span class="cnry-legend__group"><span class="cnry-legend__title">Basis</span>'
            f'<span class="cnry-legend__item">{ai_badge()}{b["judged"]} AI judgements from news reports</span>'
            f'<span class="cnry-legend__item">{b["measured"] + b["published"]} unmarked: measured data or a published figure</span>'
            f'<a class="cds--link cds--link--sm" href="/methodology#basis">How statuses are set</a></span>'
            '<span class="cnry-legend__group">Select a signal to see why, what it means for you, the rating criteria and sources.</span>')


def jsonld(m: Model) -> str:
    n = len(m.cat["signals"])
    d = {"@context": "https://schema.org", "@type": "Dataset", "name": "Canary — global risk status",
         "description": f"{n} global risk signals rated Normal, Watch or Alert four times a day by an {ASSESSED_BY}, "
                        "with sources. Attention levels, not forecasts or advice.",
         "url": f"{m.url}/", "dateModified": m.as_of, "isAccessibleForFree": True, "license": LICENCE["url"],
         "creator": {"@type": "Organization", "name": "Canary", "url": f"{m.url}/"},
         "keywords": ["global risk", "geopolitics", "markets", "extreme weather", "public health", "cyber", "UK"],
         "distribution": [
             {"@type": "DataDownload", "encodingFormat": "text/markdown", "contentUrl": f"{m.url}/now.md"},
             {"@type": "DataDownload", "encodingFormat": "application/json", "contentUrl": f"{m.url}/api/v1/status.json"},
             {"@type": "DataDownload", "encodingFormat": "application/atom+xml", "contentUrl": f"{m.url}/feed.xml"}]}
    return f'<script type="application/ld+json">{json.dumps(d, ensure_ascii=False)}</script>'


SUPPORT = {"green": "success", "amber": "warning", "red": "error"}
TREND_DAYS = 30


def world_trend_html(series: list, st: str | None) -> str:
    """Sparkline of the World State index over the last 30 days. Mirrors worldTrend() in app.js."""
    pts = [(parse(t), v) for t, v in series if parse(t) and isinstance(v, (int, float))]
    if pts:
        start = pts[-1][0] - timedelta(days=TREND_DAYS)
        pts = [p for p in pts if p[0] >= start]
    if len(pts) < 2:
        return "<figcaption>Trend line starts at the next check</figcaption>" if pts else ""
    w, h, pad = 240, 56, 4
    t0, t1 = pts[0][0].timestamp(), pts[-1][0].timestamp()
    tspan = (t1 - t0) or 1
    vals = [v for _, v in pts]
    lo, hi = min(vals), max(vals)
    if hi - lo < 10:
        mid = (lo + hi) / 2
        lo, hi = mid - 5, mid + 5
        if lo < 0:
            lo, hi = 0, 10
        elif hi > 100:
            lo, hi = 90, 100
    xy = [(pad + (t.timestamp() - t0) / tspan * (w - 2 * pad), pad + (1 - (v - lo) / (hi - lo)) * (h - 2 * pad))
          for t, v in pts]
    d = "".join(f"{'L' if i else 'M'}{x:.1f} {y:.1f}" for i, (x, y) in enumerate(xy))
    lx, ly = xy[-1]
    first, last = vals[0], vals[-1]
    since = uk_day(iso(pts[0][0]))
    diff = last - first
    delta = "No change" if diff == 0 else ("+" if diff > 0 else "\u2212") + str(abs(diff))
    label = (f"World State index at each check since {since}: {first} at the first check, {last} now; "
             f"low {min(vals)}, high {max(vals)}")
    edge = ' stroke="var(--cnry-warning-edge)"' if st == "amber" else ""
    return (f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="{e(label)}">'
            f'<path d="{d}" fill="none" stroke="var(--cds-icon-secondary)" stroke-width="1.5" '
            f'stroke-linejoin="round" stroke-linecap="round"/>'
            f'<circle cx="{lx:.1f}" cy="{ly:.1f}" r="3.5" fill="var(--cds-support-{SUPPORT.get(st, "info")})"{edge}/></svg>'
            f'<figcaption>{delta} since {since}</figcaption>')


def render_index(m: Model, doc: str) -> str:
    c = m.counts()
    w = m.world
    n, nd = len(m.cat["signals"]), len(m.cat["domains"])
    head = ('<link rel="alternate" type="text/markdown" title="Plain-text brief for AI assistants" href="/now.md">\n'
            '<link rel="alternate" type="application/json" title="Status JSON" href="/api/v1/status.json">\n'
            + jsonld(m) + "\n")
    doc = fill(doc, "head", head)
    doc = fill(doc, "updated", e(
        f"Last assessed {uk(m.as_of)} UK time. Next scheduled check about {m.next_run_uk[:5]}. "
        f"{n} signals in {nd} domains." if m.as_of else "Awaiting the first assessment."))
    doc = fill(doc, "headline", e(m.status.get("headline") or ""))
    doc = fill(doc, "kpi-score", str(w.get("score", "–")))
    doc = fill(doc, "kpi-band", f'{status_icon(w["status"])}<span>{e(w["band"])}</span>' if w.get("band") else "")
    doc = fill(doc, "kpi-trend", world_trend_html(m.world_series, w.get("status")))
    doc = fill(doc, "kpi-red", str(c["alert"]))
    doc = fill(doc, "kpi-amber", str(c["watch"]))
    doc = fill(doc, "kpi-green", str(c["normal"]))
    doc = fill(doc, "kpi-fresh", f"{c['pending']} pending" if c["pending"] else "All current")
    doc = fill(doc, "kpi-fresh-hint", e(f"As of {uk(m.as_of)} UK"))
    doc = fill(doc, "situations", situations_html(m))
    doc = fill(doc, "sentiment", sentiment_html(m))
    doc = fill(doc, "domains", domains_html(m))
    nch = len(m.changes_7d)
    doc = fill(doc, "changes-desc", e(f"{nch} status change{'' if nch == 1 else 's'} in the last 7 days, newest first"
                                      if nch else "Status changes in the last 7 days"))
    doc = fill(doc, "changes-body", changes_rows(m))
    doc = fill(doc, "legend", legend_html(m))
    doc = fill(doc, "board", board_html(m))
    doc = re.sub(r"\b\d+ global risk signals", f"{n} global risk signals", doc)
    doc = re.sub(r'id="kpi-bar"(?: style="[^"]*")?', f'id="kpi-bar" style="transform: scaleX({(w.get("score") or 0) / 100:.2f})"', doc)
    doc = re.sub(r'class="cds--tile cnry-kpi cnry-kpi--index"(?: data-status="[^"]*")?',
                 f'class="cds--tile cnry-kpi cnry-kpi--index" data-status="{e(w.get("status") or "")}"', doc)
    return version_assets(hydrate_icons(doc))


def coverage_html(m: Model) -> str:
    cov = m.coverage or {}
    risks = cov.get("risks") or []
    if not risks:
        return ""
    n = {k: sum(1 for x in risks if x.get("coverage") == k) for k in COVERAGE_LABEL}
    mapped = {i for x in risks for i in x.get("signals") or []}
    fw = cov.get("framework") or {}
    order = {"gap": 0, "partial": 1, "covered": 2}
    rows = []
    for x in sorted(risks, key=lambda x: (order.get(x.get("coverage"), 3), x.get("risk", ""))):
        lab, kind = COVERAGE_LABEL.get(x.get("coverage"), ("?", "gray"))
        sigs = ", ".join(f'<a class="cds--link cds--link--sm" href="/s/{e(i)}">{e(m.by_id[i]["name"])}</a>'
                         for i in x.get("signals") or [] if i in m.by_id) or "—"
        none = ' class="cnry-cov-none"' if sigs == "—" else ""
        rows.append(f'<tr><td>{e(x.get("risk"))}</td><td>{tag(lab, kind)}</td><td{none}>{sigs}</td>'
                    f'<td>{e(x.get("note") or "")}</td></tr>')
    head = "".join(f'<th scope="col"{w}><div class="cds--table-header-label">{h}</div></th>'
                   for h, w in (("Risk", ' style="inline-size:24%"'), ("Coverage", ' style="inline-size:9rem"'),
                                ("Canary signals", ' style="inline-size:26%"'), ("Note", "")))
    return (f'<p>Of the {len(risks)} risks in the <a class="cds--link" href="{e(fw.get("url", ""))}">{e(fw.get("name", ""))}</a>, '
            f'Canary covers {n["covered"]}, covers {n["partial"]} in part and has no signal for {n["gap"]}. '
            f'{len(mapped)} of its {len(m.cat["signals"])} signals map to at least one of them; the rest are UK-specific or '
            f'market-plumbing signals that WEF does not list separately. Reviewed {e(uk_date(str(fw.get("reviewed", "")) + "T12:00:00Z"))}.</p>'
            f'<div class="cds--data-table-content"><table class="cds--data-table cds--data-table--sm cnry-coverage" '
            f'aria-label="Coverage of WEF global risks"><thead><tr>{head}</tr></thead><tbody>{"".join(rows)}</tbody></table></div>')


def governance_html(m: Model) -> str:
    lk = m.lock or {}
    if not lk:
        return ""
    frozen = lk.get("frozen_until")
    fz = ""
    if frozen and m.as_of and frozen >= m.as_of[:10]:
        fz = (f" It is <strong>frozen until {e(uk_date(frozen + 'T12:00:00Z'))}</strong>: no signals are added or removed "
              "and no rubric changes during that time, so the first month's statuses can be compared like for like.")
    return (f'<p>The catalogue is at <strong>version {e(lk.get("version"))}</strong> ({lk.get("signals_count")} signals), '
            f'locked on {e(uk_date(lk.get("locked_at")))}.{fz} Every change is recorded in the '
            f'<a class="cds--link" href="{REPO_URL}/blob/main/signals/CHANGELOG.md">catalogue changelog</a>.</p>')


def render_methodology(m: Model, doc: str, sizes: dict) -> str:
    tables = []
    for d in m.cat["domains"]:
        rows = []
        for s in m.cat["signals"]:
            if s["domain"] != d["id"]:
                continue
            extra = f" · {HORIZON_LABEL[s['horizon']].lower()}" if s.get("horizon") in HORIZON_LABEL else ""
            if s.get("metrics"):
                extra += " · open data sets a floor"
            if s.get("published"):
                extra += f" · follows {s['published']['by']}"
            rows.append(f'<tr id="r-{s["id"]}"><td><strong><a class="cnry-sig__link" href="/s/{s["id"]}">{e(s["name"])}</a></strong><br>'
                        f'<span class="cds--type-helper-text-01">{"Checked daily" if s["tier"] == "daily" else "Checked every run"}{extra}</span></td>'
                        f'<td>{e(s["rubric"]["green"])}</td><td>{e(s["rubric"]["amber"])}</td><td>{e(s["rubric"]["red"])}</td></tr>')
        lvl = lambda k: f'<span class="cnry-rubric-level">{status_icon(k)}{LABEL[k]}</span>'  # noqa: E731
        tables.append(f"""<div class="cds--data-table-container cnry-rubric-domain">
<div class="cds--data-table-header"><h3 class="cds--data-table-header__title">{e(d['name'])}</h3><p class="cds--data-table-header__description">Domain weight {d['weight']}</p></div>
<div class="cds--data-table-content"><table class="cds--data-table cds--data-table--sm" aria-label="{e(d['name'])} rubrics">
<thead><tr><th scope="col" style="inline-size:22%"><div class="cds--table-header-label">Signal</div></th><th scope="col"><div class="cds--table-header-label">{lvl('green')}</div></th><th scope="col"><div class="cds--table-header-label">{lvl('amber')}</div></th><th scope="col"><div class="cds--table-header-label">{lvl('red')}</div></th></tr></thead>
<tbody>{''.join(rows)}</tbody></table></div></div>""")
    doc = fill(doc, "rubrics", "".join(tables))
    size_rows = "".join(
        f'<div class="cds--structured-list-row" role="row"><div class="cds--structured-list-td" role="cell">'
        f'<a class="cds--link" href="/{k}"><code>/{k}</code></a></div><div class="cds--structured-list-td" role="cell">{what}</div>'
        f'<div class="cds--structured-list-td cnry-num" role="cell">{approx(sizes[k])}</div></div>'
        for k, what in (("now.md", "Brief: situations, every Alert, 24h changes, Watch ids"),
                        ("status.md", "Every signal, one row"), ("changes.md", "Status changes, last 7 days"),
                        ("api/v1/meta.json", "Run metadata — poll this first"),
                        ("api/v1/status.json", "Full state as JSON"), ("api/v1/catalogue.json", "Signal definitions and rubrics"),
                        ("api/v1/sentiment.json", "Sentiment track: news tone, consumer confidence, uncertainty")))
    doc = fill(doc, "agent-sizes", size_rows)
    doc = fill(doc, "sentiment-method", sentiment_method_html(m.sentiment_cfg))
    b = m.basis_counts()
    doc = fill(doc, "basis-counts", e(f"At the latest run: {b['measured']} measured, {b['published']} published "
                                      f"figures and {b['judged']} AI judgements, out of {sum(b.values())} assessed signals."))
    doc = fill(doc, "coverage", coverage_html(m))
    doc = fill(doc, "governance", governance_html(m))
    n = len(m.cat["signals"])
    doc = re.sub(r"\b\d+ global risk signals", f"{n} global risk signals", doc)
    return version_assets(hydrate_icons(doc))


# ───────────────────────── entry point ─────────────────────────

def build(site_url: str, cat: dict, status: dict, changes: list, history: dict, metrics: dict,
          stale_h: dict, world: list | None = None, sentiment: dict | None = None,
          sentiment_cfg: dict | None = None, coverage: dict | None = None, lock: dict | None = None) -> list[str]:
    global ICONS, ASSET_V
    ICONS = load_icons()
    ASSET_V = asset_versions()
    m = Model(site_url, cat, status, changes, history, metrics, stale_h)
    m.world_series = world or []
    m.sentiment, m.sentiment_cfg = sentiment or {}, sentiment_cfg
    m.coverage, m.lock = coverage, lock
    m.sentiment_v = sentiment_view(m)
    written: list[str] = []

    texts = {"now.md": now_md(m), "status.md": status_md(m), "changes.md": changes_md(m)}
    api = {"api/v1/status.json": dump(status_json(m)),
           "api/v1/changes.json": dump({**envelope(m), "changes": [
               {**c, "from": PUBLIC[c["from"]], "to": PUBLIC[c["to"]], "url": f"{m.url}/s/{c['id']}"}
               for c in changes[:200]]}),
           "api/v1/catalogue.json": dump(catalogue_json(m)),
           "api/v1/sentiment.json": dump(sentiment_json(m)),
           "api/v1/schema.json": json.dumps(schema_json(m), ensure_ascii=False, indent=1) + "\n"}
    sizes = {k: est_tokens(v) for k, v in {**texts, **api}.items()}
    meta = dump(meta_json(m, {**sizes, "api/v1/meta.json": 0}))
    sizes["api/v1/meta.json"] = est_tokens(meta)
    api["api/v1/meta.json"] = dump(meta_json(m, sizes))

    for k, v in {**texts, **api}.items():
        write(SITE / k, v, written)
    sig_md = {r["id"]: signal_md(m, r) for r in m.records}
    assessed = sorted(est_tokens(v) for k, v in sig_md.items() if m.rec[k]["status"] != "pending") or [0]
    sizes["s/{id}.md"] = assessed[len(assessed) // 2]
    for r in m.records:
        write(SITE / "s" / f"{r['id']}.md", sig_md[r["id"]], written)
        write(SITE / "s" / f"{r['id']}.json", dump(signal_json(m, r)), written)
        write(SITE / "s" / f"{r['id']}.html", signal_html(m, r), written)
    write(SITE / "llms.txt", llms_txt(m, sizes), written)
    write(SITE / "openapi.json", json.dumps(openapi_json(m), ensure_ascii=False, indent=1) + "\n", written)
    write(SITE / "robots.txt", robots_txt(m), written)
    write(SITE / "sitemap.xml", sitemap_xml(m), written)
    write(SITE / "feed.xml", feed_xml(m, texts["now.md"]), written)
    write(SITE / "404.html", not_found_html(m), written)
    write(SITE / "index.html", render_index(m, (SITE / "index.html").read_text()), written)
    write(SITE / "methodology.html", render_methodology(m, (SITE / "methodology.html").read_text(), sizes), written)
    # drop pages for signals that no longer exist in the catalogue
    keep = {r["id"] for r in m.records}
    for f in (SITE / "s").glob("*.*"):
        if f.stem not in keep:
            f.unlink()
            written.append(str(f.relative_to(ROOT)))
    return written
