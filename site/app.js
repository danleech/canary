/* Canary board — vanilla JS, no dependencies. Reads ./data/*.json and renders the page. */
(() => {
  "use strict";

  const LABEL = { green: "Normal", amber: "Watch", red: "Alert", stale: "Not checked recently", pending: "Not yet assessed" };
  const TREND = { up: { g: "↑", t: "Worsening" }, flat: { g: "→", t: "Stable" }, down: { g: "↓", t: "Easing" } };
  const STALE_H = { fast: 14, daily: 36 };
  const RUN_TIMES = ["05:40", "11:40", "17:40", "23:40"]; // UK local
  const SPARK_SKIP = new Set(["sea_ice", "quakes", "gdacs", "swpc", "metoffice"]);
  const $ = (s, el = document) => el.querySelector(s);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* storage unavailable */ } },
  };

  let D = {}; // data
  let lastFocus = null;

  async function getJSON(name, fallback) {
    try {
      const r = await fetch(`data/${name}`, { cache: "no-cache" });
      if (!r.ok) throw new Error(r.status);
      return await r.json();
    } catch (e) {
      if (fallback !== undefined) return fallback;
      throw e;
    }
  }

  // ───────── time helpers ─────────
  const ukFmt = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
  const ukDate = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", day: "numeric", month: "short", year: "numeric" });
  function ago(iso) {
    const ms = Date.now() - new Date(iso).getTime();
    const h = ms / 36e5;
    if (h < 1) return `${Math.max(1, Math.round(ms / 6e4))}m`;
    if (h < 48) return `${Math.round(h)}h`;
    return `${Math.round(h / 24)}d`;
  }
  function agoLong(iso) {
    const a = ago(iso);
    const n = parseInt(a, 10);
    const u = a.slice(-1);
    return `${n} ${u === "m" ? "minute" : u === "h" ? "hour" : "day"}${n === 1 ? "" : "s"} ago`;
  }
  function nextRun() {
    const parts = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/London", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date());
    const nxt = RUN_TIMES.find((t) => t > parts) || RUN_TIMES[0];
    return nxt;
  }

  // ───────── status helpers ─────────
  function effective(sig, cur) {
    if (!cur || !cur.status) return "pending";
    const h = (Date.now() - new Date(cur.checked_at).getTime()) / 36e5;
    return h > STALE_H[sig.tier] ? "stale" : cur.status;
  }
  const shape = (st) => `<i class="shape s-${st === "pending" ? "stale" : st}" aria-hidden="true"></i>`;

  function seriesFor(sig) {
    for (const k of sig.metrics || []) {
      if (SPARK_SKIP.has(k)) continue;
      const m = D.metrics[k];
      if (m && Array.isArray(m.series) && m.series.length > 3) return { key: k, series: m.series, m };
    }
    const h = (D.history[sig.id] || []).map((p) => p[2]).filter((v) => typeof v === "number");
    return h.length > 3 ? { key: null, series: h } : null;
  }

  function sparkSVG(series, st, w = 54, h = 16, pad = 1.5) {
    const min = Math.min(...series), max = Math.max(...series);
    const span = max - min || 1;
    const pts = series.map((v, i) => [pad + (i / (series.length - 1)) * (w - pad * 2), h - pad - ((v - min) / span) * (h - pad * 2)]);
    const d = pts.map((p, i) => `${i ? "L" : "M"}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join("");
    const [lx, ly] = pts[pts.length - 1];
    const col = st === "stale" || st === "pending" ? "var(--stale)" : `var(--${st})`;
    return `<svg class="spark" viewBox="0 0 ${w} ${h}" aria-hidden="true"><path d="${d}" fill="none" stroke="var(--muted)" stroke-width="1.1" stroke-linejoin="round" stroke-linecap="round"/><circle cx="${lx}" cy="${ly}" r="2" fill="${col}"/></svg>`;
  }

  function bigChart(s) {
    const w = 500, h = 90, pad = 4;
    const v = s.series, min = Math.min(...v), max = Math.max(...v), span = max - min || 1;
    const pts = v.map((y, i) => [pad + (i / (v.length - 1)) * (w - pad * 2), h - pad - ((y - min) / span) * (h - pad * 2)]);
    const line = pts.map((p, i) => `${i ? "L" : "M"}${p[0].toFixed(1)},${p[1].toFixed(1)}`).join("");
    const area = `${line}L${pts[pts.length - 1][0]},${h}L${pts[0][0]},${h}Z`;
    const fmt = (x) => (Math.abs(x) >= 1000 ? x.toLocaleString("en-GB", { maximumFractionDigits: 0 }) : (+x.toFixed(2)).toString());
    return `<figure class="d-chart"><svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" role="img" aria-label="Recent values, low ${fmt(min)}, high ${fmt(max)}">
      <path d="${area}" fill="var(--paper-2)"/><path d="${line}" fill="none" stroke="var(--ink)" stroke-width="1.4" vector-effect="non-scaling-stroke"/></svg>
      <figcaption>Last ${v.length} readings${s.m ? ` from ${esc(s.m.source)}` : ""}. Low ${fmt(min)}, high ${fmt(max)}, latest ${fmt(v[v.length - 1])}.</figcaption></figure>`;
  }

  // ───────── render ─────────
  function renderMast() {
    const g = D.status.generated_at;
    $("#updated").textContent = g ? `Updated ${ukFmt.format(new Date(g))} UK time. Next check about ${nextRun()}.` : "Awaiting first assessment";
  }

  function renderHero() {
    const w = D.status.world || {};
    const sc = $("#world-score");
    sc.innerHTML = w.score == null ? "–" : `<small>World State, 0–100</small>${w.score}`;
    $("#world-band").innerHTML = w.band ? `${shape(w.status)}${esc(w.band)}` : "";
    const c = w.counts || {};
    $("#world-counts").innerHTML = `<b>${c.red || 0}</b> Alert, <b>${c.amber || 0}</b> Watch, <b>${c.green || 0}</b> Normal across ${D.cat.signals.length} signals`;
    $("#headline").textContent = D.status.headline || "";

    const strip = $("#strip");
    let i = 0;
    strip.innerHTML = D.cat.domains.map((d) => {
      const sigs = D.cat.signals.filter((s) => s.domain === d.id);
      const ticks = sigs.map((s) => {
        const st = effective(s, D.status.signals[s.id]);
        return `<button class="tick ${st === "pending" ? "stale" : st}" style="--i:${i++}" data-id="${s.id}" role="listitem" aria-label="${esc(s.name)}: ${LABEL[st]}"></button>`;
      }).join("");
      return `<div class="strip-group" style="--n:${sigs.length}"><div class="strip-ticks">${ticks}</div><div class="strip-label" title="${esc(d.name)}">${esc(d.short || d.name)}</div></div>`;
    }).join("");

    const tip = document.createElement("div");
    tip.className = "tip"; tip.hidden = true; document.body.appendChild(tip);
    strip.addEventListener("pointerover", (e) => {
      const t = e.target.closest(".tick"); if (!t) return;
      tip.textContent = t.getAttribute("aria-label"); tip.hidden = false;
      const r = t.getBoundingClientRect();
      tip.style.left = `${Math.min(window.innerWidth - 270, Math.max(8, r.left - 20))}px`;
      tip.style.top = `${r.top - 34}px`;
    });
    strip.addEventListener("pointerout", () => { tip.hidden = true; });
    strip.addEventListener("click", (e) => { const t = e.target.closest(".tick"); if (t) open(t.dataset.id); });
  }

  function renderChanges() {
    const since = Date.now() - 864e5;
    const recent = (D.changes || []).filter((c) => new Date(c.t).getTime() > since);
    if (!recent.length) return;
    $("#changes").hidden = false;
    $("#changes-list").innerHTML = recent.slice(0, 16).map((c) =>
      `<li><button data-id="${c.id}">${shape(c.to)}<span class="c-name">${esc(c.name)}</span><span class="c-move">${LABEL[c.from]} to ${LABEL[c.to]}, ${ago(c.t)} ago</span></button></li>`).join("");
    $("#changes-list").addEventListener("click", (e) => { const b = e.target.closest("button"); if (b) open(b.dataset.id); });
  }

  function renderBoard() {
    const since = Date.now() - 864e5;
    const changed = new Set((D.changes || []).filter((c) => new Date(c.t).getTime() > since).map((c) => c.id));
    $("#board").innerHTML = D.cat.domains.map((d) => {
      const sigs = D.cat.signals.filter((s) => s.domain === d.id);
      const tally = { red: 0, amber: 0, green: 0 };
      const rows = sigs.map((s) => {
        const cur = D.status.signals[s.id];
        const st = effective(s, cur);
        if (tally[st] !== undefined) tally[st]++;
        if (!cur) {
          return `<li class="row pending" id="${s.id}"><button data-id="${s.id}" aria-label="${esc(s.name)}: not yet assessed">${shape("pending")}<span class="r-name">${esc(s.name)}</span><span class="r-right"><span class="r-age">–</span></span><span class="r-sub"><span class="r-sum">Not yet assessed</span></span></button></li>`;
        }
        const tr = TREND[cur.trend] || TREND.flat;
        const sp = seriesFor(s);
        const isStale = st === "stale";
        return `<li class="row st-${cur.status}${changed.has(s.id) ? " fresh" : ""}" id="${s.id}">
          <button data-id="${s.id}" aria-label="${esc(s.name)}: ${LABEL[st]}, ${tr.t}. ${esc(cur.summary)}">
            ${shape(st)}
            <span class="r-name">${esc(s.name)}</span>
            <span class="r-right">${sp ? sparkSVG(sp.series, st) : ""}<span class="r-trend ${cur.trend}" title="${tr.t}">${tr.g}</span><span class="r-age${isStale ? " is-stale" : ""}" title="Checked ${esc(ukFmt.format(new Date(cur.checked_at)))}">${isStale ? "stale" : ago(cur.checked_at)}</span></span>
            <span class="r-sub">${cur.value ? `<span class="r-value">${esc(cur.value)}</span>` : ""}<span class="r-sum">${esc(cur.summary)}</span></span>
          </button></li>`;
      }).join("");
      const allGreen = !tally.red && !tally.amber;
      const t = [["red", tally.red], ["amber", tally.amber], ["green", tally.green]].filter(([, n]) => n)
        .map(([k, n]) => `<span title="${n} ${LABEL[k]}">${shape(k)}${n}</span>`).join("");
      return `<section class="domain${allGreen ? " all-green" : ""}" aria-labelledby="h-${d.id}"><div class="domain-head"><h2 id="h-${d.id}">${esc(d.name)}</h2><span class="domain-tally">${t}</span></div><ul class="rows">${rows}</ul></section>`;
    }).join("");
    $("#board").addEventListener("click", (e) => { const b = e.target.closest("button[data-id]"); if (b) open(b.dataset.id); });
  }

  function open(id, push = true) {
    const s = D.cat.signals.find((x) => x.id === id);
    if (!s) return;
    const cur = D.status.signals[id];
    const st = effective(s, cur);
    const dom = D.cat.domains.find((d) => d.id === s.domain);
    const tr = cur ? TREND[cur.trend] || TREND.flat : null;
    const sp = seriesFor(s);
    const hist = (D.history[id] || []).slice(-60);
    const body = [];
    body.push(`<p class="d-domain">${esc(dom ? dom.name : "")}</p><h2 class="d-title" id="d-title">${esc(s.name)}</h2>`);
    body.push(`<div class="d-status"><span class="pill ${st === "pending" ? "stale" : st}">${shape(st)}${LABEL[st]}</span>${tr ? `<span>${tr.g} ${tr.t}</span>` : ""}${cur && cur.value ? `<span class="d-value">${esc(cur.value)}</span>` : ""}</div>`);
    if (cur) {
      body.push(`<p class="d-summary">${esc(cur.summary)}</p>`);
      body.push(`<div class="d-sec"><h3>Why it's at this level</h3><p>${esc(cur.state)}</p></div>`);
      body.push(`<div class="d-sec"><h3>What this means for you</h3><p>${esc(cur.for_you)}</p></div>`);
      if (sp && sp.series.length > 3) body.push(bigChart(sp));
    } else {
      body.push(`<p class="d-summary">This signal hasn't been assessed yet.</p>`);
    }
    body.push(`<div class="d-sec quiet"><h3>Why it matters</h3><p>${esc(s.why)}</p></div>`);
    body.push(`<div class="d-sec quiet"><h3>What moves it</h3><p>${esc(s.drivers)}</p></div>`);
    body.push(`<div class="d-sec"><h3>How it's rated</h3><ul class="rubric">${["green", "amber", "red"].map((k) =>
      `<li class="${cur && cur.status === k ? "on" : ""}"><b>${shape(k)}${LABEL[k]}</b><span>${esc(s.rubric[k])}</span></li>`).join("")}</ul></div>`);
    if (hist.length > 1) {
      body.push(`<div class="d-sec"><h3>Status over the last ${hist.length} checks</h3><div class="d-hist" role="img" aria-label="Status history">${hist.map((p) => `<i class="${p[1]}" title="${esc(ukFmt.format(new Date(p[0])))}: ${LABEL[{ g: "green", a: "amber", r: "red" }[p[1]]]}"></i>`).join("")}</div></div>`);
    }
    if (cur && cur.sources && cur.sources.length) {
      body.push(`<div class="d-sec"><h3>Sources</h3><ol class="sources">${cur.sources.map((x) =>
        `<li><a href="${esc(x.url)}" rel="noopener nofollow" target="_blank">${esc(x.title)}</a>${x.date ? ` <span>${esc(ukDate.format(new Date(x.date)))}</span>` : ""}</li>`).join("")}</ol></div>`);
    }
    if (cur) {
      body.push(`<div class="d-meta"><p>Checked ${esc(ukFmt.format(new Date(cur.checked_at)))} (${agoLong(cur.checked_at)}). ${s.tier === "daily" ? "Re-assessed once a day." : "Re-assessed every run."}</p>${cur.changed_at ? `<p>At this level since ${esc(ukFmt.format(new Date(cur.changed_at)))}.</p>` : ""}${cur.override_reason ? `<p>Assessor note: ${esc(cur.override_reason)}</p>` : ""}</div>`);
    }
    $("#drawer-body").innerHTML = body.join("");
    lastFocus = document.activeElement;
    $("#scrim").hidden = false;
    const dr = $("#drawer");
    dr.hidden = false;
    dr.scrollTop = 0;
    dr.focus();
    document.body.style.overflow = "hidden";
    if (push && location.hash !== `#${id}`) history.pushState(null, "", `#${id}`);
  }

  function close(push = true) {
    $("#drawer").hidden = true;
    $("#scrim").hidden = true;
    document.body.style.overflow = "";
    if (push && location.hash) history.pushState(null, "", location.pathname + location.search);
    if (lastFocus) lastFocus.focus();
  }

  function wire() {
    $("#drawer-close").addEventListener("click", () => close());
    $("#scrim").addEventListener("click", () => close());
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape" && !$("#drawer").hidden) close();
      if (e.key === "Tab" && !$("#drawer").hidden) {
        const f = [...$("#drawer").querySelectorAll("a, button")];
        if (!f.length) return;
        if (e.shiftKey && document.activeElement === f[0]) { e.preventDefault(); f[f.length - 1].focus(); }
        else if (!e.shiftKey && document.activeElement === f[f.length - 1]) { e.preventDefault(); f[0].focus(); }
      }
    });
    window.addEventListener("popstate", () => {
      const id = location.hash.slice(1);
      if (id) open(id, false); else if (!$("#drawer").hidden) close(false);
    });
    const cb = $("#only-flagged");
    cb.checked = store.get("canary.flagged") === "1";
    $("#board").classList.toggle("flagged", cb.checked);
    cb.addEventListener("change", () => {
      $("#board").classList.toggle("flagged", cb.checked);
      store.set("canary.flagged", cb.checked ? "1" : "0");
    });
  }

  async function init() {
    try {
      const [cat, status, metrics, history, changes] = await Promise.all([
        getJSON("catalogue.json"), getJSON("status.json", { signals: {} }),
        getJSON("metrics.json", { metrics: {} }), getJSON("history.json", {}), getJSON("changes.json", []),
      ]);
      D = { cat, status: { signals: {}, ...status }, metrics: metrics.metrics || {}, history, changes };
      renderMast(); renderHero(); renderChanges(); renderBoard(); wire();
      const id = location.hash.slice(1);
      if (id) open(id, false);
    } catch (e) {
      const el = $("#error");
      el.hidden = false;
      el.textContent = "Canary couldn't load its data. Refresh the page; if it keeps happening, the latest update may still be deploying.";
      console.error(e);
    }
  }

  init();
})();
