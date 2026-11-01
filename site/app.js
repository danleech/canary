/* Canary board — vanilla JS on IBM Carbon markup. Reads ./data/*.json. */
(() => {
  'use strict';

  const LABEL = { green: 'Normal', amber: 'Watch', red: 'Alert', stale: 'Stale', pending: 'Pending' };
  const ICON_FOR = { green: 'checkmark--filled', amber: 'warning--alt--filled', red: 'error--filled', stale: 'circle-dash', pending: 'circle-dash' };
  const TREND = {
    up: { icon: 'arrow--up-right', text: 'Worsening' },
    flat: { icon: 'arrow--right', text: 'Stable' },
    down: { icon: 'arrow--down-right', text: 'Easing' },
  };
  const STALE_H = { fast: 14, daily: 36 };
  const RUN_TIMES = ['05:40', '11:40', '17:40', '23:40'];
  const SPARK_SKIP = new Set(['sea_ice', 'quakes', 'gdacs', 'swpc', 'metoffice']);
  const COLS = 4;

  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* storage unavailable */ } },
  };

  // Carbon icons (from assets/icons.js, generated from @carbon/icons)
  function icon(name, cls = '', label = '') {
    const i = (window.CARBON_ICONS || {})[name];
    if (!i) return '';
    const a11y = label ? `role="img" aria-label="${esc(label)}"` : 'aria-hidden="true" focusable="false"';
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${i.viewBox}" width="16" height="16" fill="currentColor" class="${cls}" ${a11y}>${i.inner}</svg>`;
  }
  function hydrateIcons(root = document) {
    $$('[data-icon]', root).forEach((el) => { if (!el.querySelector('svg')) el.insertAdjacentHTML('afterbegin', icon(el.dataset.icon)); });
  }
  const statusIcon = (st, label) => `<span class="cnry-icon cnry-st--${st}">${icon(ICON_FOR[st], '', label)}</span>`;
  const statusIndicator = (st) => `<span class="cnry-status">${statusIcon(st)}<span class="cnry-status__label">${LABEL[st]}</span></span>`;
  const trendCell = (t) => { const x = TREND[t] || TREND.flat; return `<span class="cnry-trend cnry-trend--${t || 'flat'}">${icon(x.icon)}<span>${x.text}</span></span>`; };
  const trendIcon = (t) => { const x = TREND[t] || TREND.flat; return `<span class="cnry-trend cnry-trend--${t || 'flat'}" title="Trend: ${x.text}">${icon(x.icon, '', 'Trend: ' + x.text)}</span>`; };
  const statusOnly = (st) => `<span class="cnry-icon cnry-st--${st}" title="Status: ${LABEL[st]}">${icon(ICON_FOR[st], '', 'Status: ' + LABEL[st])}</span>`;

  // Time
  const fmtUK = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/London', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  const fmtDate = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/London', day: 'numeric', month: 'short', year: 'numeric' });
  const hoursSince = (iso) => (Date.now() - new Date(iso).getTime()) / 36e5;
  function ago(iso, long = false) {
    const h = hoursSince(iso);
    if (h < 1) { const m = Math.max(1, Math.round(h * 60)); return long ? `${m} min ago` : `${m}m`; }
    if (h < 48) { const r = Math.round(h); return long ? `${r} hour${r === 1 ? '' : 's'} ago` : `${r}h`; }
    const d = Math.round(h / 24); return long ? `${d} days ago` : `${d}d`;
  }
  function nextRun() {
    const now = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/London', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date());
    return RUN_TIMES.find((t) => t > now) || RUN_TIMES[0];
  }

  let D = {};
  const state = { status: 'all', text: '' };

  async function getJSON(name, fallback) {
    try {
      const r = await fetch(`data/${name}`, { cache: 'no-cache' });
      if (!r.ok) throw new Error(r.status);
      return await r.json();
    } catch (e) { if (fallback !== undefined) return fallback; throw e; }
  }

  function effective(sig) {
    const cur = D.status.signals[sig.id];
    if (!cur || !cur.status) return 'pending';
    return hoursSince(cur.checked_at) > STALE_H[sig.tier] ? 'stale' : cur.status;
  }

  function seriesFor(sig) {
    for (const k of sig.metrics || []) {
      if (SPARK_SKIP.has(k)) continue;
      const m = D.metrics[k];
      if (m && Array.isArray(m.series) && m.series.length > 3) return { series: m.series, m };
    }
    const h = (D.history[sig.id] || []).map((p) => p[2]).filter((v) => typeof v === 'number');
    return h.length > 3 && new Set(h).size > 1 ? { series: h } : null; // a flat line adds nothing
  }

  function sparkSVG(series, st) {
    const w = 72, h = 20, p = 2;
    const min = Math.min(...series), max = Math.max(...series), span = max - min || 1;
    const pts = series.map((v, i) => [p + (i / (series.length - 1)) * (w - 2 * p), h - p - ((v - min) / span) * (h - 2 * p)]);
    const d = pts.map((q, i) => `${i ? 'L' : 'M'}${q[0].toFixed(1)} ${q[1].toFixed(1)}`).join('');
    const [lx, ly] = pts[pts.length - 1];
    return `<svg class="cnry-spark" viewBox="0 0 ${w} ${h}" aria-hidden="true"><path d="${d}" fill="none" stroke="var(--cds-icon-secondary)" stroke-width="1"/><circle cx="${lx}" cy="${ly}" r="2.25" fill="var(--cds-support-${st === 'green' ? 'success' : st === 'amber' ? 'warning' : st === 'red' ? 'error' : 'info'})"/></svg>`;
  }

  function chartSVG(s) {
    const v = s.series, w = 480, h = 120, l = 44, r = 8, t = 8, b = 18;
    const min = Math.min(...v), max = Math.max(...v), span = max - min || 1;
    const X = (i) => l + (i / (v.length - 1)) * (w - l - r);
    const Y = (y) => t + (1 - (y - min) / span) * (h - t - b);
    const line = v.map((y, i) => `${i ? 'L' : 'M'}${X(i).toFixed(1)} ${Y(y).toFixed(1)}`).join('');
    const area = `${line}L${X(v.length - 1)} ${h - b}L${X(0)} ${h - b}Z`;
    const fmt = (x) => (Math.abs(x) >= 1000 ? Math.round(x).toLocaleString('en-GB') : (+x.toFixed(2)).toString());
    const ticks = [max, (max + min) / 2, min];
    const grid = ticks.map((y) => `<line x1="${l}" x2="${w - r}" y1="${Y(y)}" y2="${Y(y)}" stroke="var(--cds-border-subtle)"/><text x="${l - 6}" y="${Y(y) + 3}" text-anchor="end">${fmt(y)}</text>`).join('');
    return `<figure class="cnry-chart"><svg viewBox="0 0 ${w} ${h}" role="img" aria-label="Recent values from ${fmt(min)} to ${fmt(max)}; latest ${fmt(v[v.length - 1])}">
      ${grid}<path d="${area}" fill="var(--cds-link-primary)" opacity="0.08"/><path d="${line}" fill="none" stroke="var(--cds-link-primary)" stroke-width="1.5"/>
      <text x="${l}" y="${h - 4}">${v.length} readings ago</text><text x="${w - r}" y="${h - 4}" text-anchor="end">Latest ${fmt(v[v.length - 1])}</text></svg>
      ${s.m ? `<figcaption>Source: ${esc(s.m.source)}</figcaption>` : '<figcaption>Recorded at each Canary check</figcaption>'}</figure>`;
  }

  // ───────── Page header + KPIs ─────────
  function renderSummary() {
    const g = D.status.generated_at;
    $('#updated').textContent = g
      ? `Last assessed ${fmtUK.format(new Date(g))} UK time (${ago(g, true)}). Next scheduled check about ${nextRun()}. ${D.cat.signals.length} signals in ${D.cat.domains.length} domains.`
      : 'Awaiting the first assessment.';

    const w = D.status.world || {};
    $('#kpi-score').textContent = w.score ?? '–';
    const idx = $('.cnry-kpi--index');
    idx.dataset.status = w.status || '';
    $('#kpi-band').innerHTML = w.band ? `${statusIcon(w.status)}<span>${esc(w.band)}</span>` : '';
    $('#kpi-bar').style.transform = `scaleX(${(w.score || 0) / 100})`;

    const counts = { red: 0, amber: 0, green: 0 };
    let stale = 0, pending = 0, oldest = null;
    D.cat.signals.forEach((s) => {
      const st = effective(s);
      if (counts[st] !== undefined) counts[st]++;
      if (st === 'stale') stale++;
      if (st === 'pending') pending++;
      const c = D.status.signals[s.id];
      if (c && (!oldest || c.checked_at < oldest)) oldest = c.checked_at;
    });
    $('#kpi-red').textContent = counts.red;
    $('#kpi-amber').textContent = counts.amber;
    $('#kpi-green').textContent = counts.green;

    $('#kpi-fresh').textContent = [stale && `${stale} stale`, pending && `${pending} pending`].filter(Boolean).join(', ') || 'All current';
    $('#kpi-fresh-hint').textContent = oldest ? `Oldest check ${ago(oldest, true)}` : '';
  }

  function renderDomains() {
    $('#domains').innerHTML = D.cat.domains.map((d) => {
      const sigs = D.cat.signals.filter((s) => s.domain === d.id);
      const score = (D.status.world?.by_domain || {})[d.id];
      const cells = sigs.map((s) => { const st = effective(s); return `<span class="cnry-icon cnry-st--${st}" title="${esc(s.name)}: ${LABEL[st]}">${icon(ICON_FOR[st])}</span>`; }).join('');
      const n = sigs.reduce((a, s) => { const st = effective(s); a[st] = (a[st] || 0) + 1; return a; }, {});
      const sr = ['red', 'amber', 'green', 'stale', 'pending'].filter((k) => n[k]).map((k) => `${n[k]} ${LABEL[k]}`).join(', ');
      return `<li class="cnry-domain"><a href="#domain-${d.id}" aria-label="${esc(d.name)}: score ${score ?? 'not available'}; ${sr}">
        <span class="cnry-domain__name">${esc(d.name)}</span>
        <span class="cnry-domain__score">${score ?? '–'}<small>/100</small></span>
        <span class="cnry-cells" aria-hidden="true">${cells}</span></a></li>`;
    }).join('');
  }

  const sigLink = (s) => `<a class="cnry-sig__link" href="#${s.id}" data-goto="${s.id}">${esc(s.name)}</a>`;

  function renderLegend() {
    const st = ['red', 'amber', 'green', 'stale'].map((k) => `<span class="cnry-legend__item">${statusIcon(k)}${LABEL[k]}</span>`).join('');
    const tr = ['up', 'flat', 'down'].map((k) => `<span class="cnry-legend__item cnry-trend cnry-trend--${k}">${icon(TREND[k].icon)}<span>${TREND[k].text}</span></span>`).join('');
    $('#legend').innerHTML = `<span class="cnry-legend__group"><span class="cnry-legend__title">Status</span>${st}</span>
      <span class="cnry-legend__group"><span class="cnry-legend__title">Trend</span>${tr}</span>
      <span class="cnry-legend__group">Select a row to see why, what it means for you, the rating criteria and sources.</span>`;
  }

  function renderChanges() {
    const MAX = 8;
    const all = (D.changes || []).filter((c) => hoursSince(c.t) < 24 * 7);
    const rows = all.slice(0, MAX);
    $('#changes-desc').textContent = all.length
      ? `${all.length} status change${all.length === 1 ? '' : 's'} in the last 7 days, newest first`
      : 'Status changes in the last 7 days';
    $('#changes-body').innerHTML = rows.length ? rows.map((c) => {
      const s = D.cat.signals.find((x) => x.id === c.id);
      return `<tr><td><span class="cnry-sig">${statusIcon(c.to, LABEL[c.to])}<span class="cnry-sig__name">${s ? sigLink(s) : esc(c.name)}</span></span></td>
        <td><span class="cnry-change">${LABEL[c.from]} ${icon('arrow--right', '', 'to')} ${LABEL[c.to]}</span></td>
        <td class="cnry-num cnry-when" title="${esc(fmtUK.format(new Date(c.t)))}">${ago(c.t, true)}</td></tr>`;
    }).join('') : `<tr class="cnry-empty-row"><td colspan="3">No status changes in the last 7 days.</td></tr>`;
    $('#changes-more').innerHTML = all.length > MAX
      ? `${all.length - MAX} older change${all.length - MAX === 1 ? '' : 's'} not shown. <a class="cds--link cds--link--sm" href="feed.xml">Full history in the status change feed</a>`
      : `<a class="cds--link cds--link--sm" href="feed.xml">Subscribe to status changes</a> · <a class="cds--link cds--link--sm" href="/changes.md">Plain text</a>`;
  }


  // ───────── Domain tables with Carbon expandable rows ─────────
  function renderBoard() {
    const fresh = new Set((D.changes || []).filter((c) => hoursSince(c.t) < 24).map((c) => c.id));
    const tables = D.cat.domains.map((d) => {
      const sigs = D.cat.signals.filter((s) => s.domain === d.id);
      const n = sigs.reduce((a, s) => { const st = effective(s); a[st] = (a[st] || 0) + 1; return a; }, {});
      const tally = ['red', 'amber', 'green', 'stale', 'pending'].filter((k) => n[k])
        .map((k) => `<span class="cnry-tally">${statusIcon(k)}${n[k]} ${LABEL[k]}</span>`).join('');
      const rows = sigs.map((s) => {
        const c = D.status.signals[s.id];
        const st = effective(s);
        const changed = fresh.has(s.id) ? ' <span class="cds--tag cds--tag--blue cds--tag--sm cnry-changed"><span class="cds--tag__label">Changed</span></span>' : '';
        return `<tr class="cds--parent-row" data-parent-row data-id="${s.id}" data-st="${st}" id="${s.id}">
            <td class="cds--table-expand w-expand"><button type="button" class="cds--table-expand__button" aria-expanded="false" aria-controls="x-${s.id}" aria-label="Show details for ${esc(s.name)}">${icon('chevron--right', 'cds--table-expand__svg')}</button></td>
            <td class="w-status">${statusOnly(st)}</td>
            <td class="w-signal"><span class="cnry-sig__name">${esc(s.name)}</span>${changed}<span class="cnry-sig__reading">${c?.value ? esc(c.value) : '<span class="cnry-none">No reading yet</span>'}</span></td>
            <td class="w-trend">${c ? trendIcon(c.trend) : ''}</td>
          </tr>
          <tr class="cds--expandable-row" data-child-row id="x-${s.id}" data-id="${s.id}" hidden><td colspan="${COLS}"><div class="cds--child-row-inner-container"></div></td></tr>`;
      }).join('');
      const el = document.createElement('div');
      el.className = 'cds--data-table-container cnry-domain-table';
      el.id = `domain-${d.id}`;
      el.dataset.domain = d.id;
      el.dataset.weight = String(sigs.length + 3);
      el.innerHTML = `<div class="cds--data-table-header">
          <h3 class="cds--data-table-header__title">${esc(d.name)}</h3>
          <p class="cds--data-table-header__description">${tally}</p>
        </div>
        <div class="cds--data-table-content">
          <table class="cds--data-table cds--data-table--sm cnry-dt" aria-label="${esc(d.name)} signals">
            <tbody>${rows}</tbody>
          </table>
        </div>`;
      return el;
    });
    layoutBoard(tables);
  }

  // Multi-column layout: contiguous domain groups balanced by row count. Each column
  // stacks its tables, so expanding a row never moves tables between columns.
  const MQ3 = matchMedia('(min-width: 82rem)');
  const MQ2 = matchMedia('(min-width: 60rem)');
  function layoutBoard(tables = $$('.cnry-domain-table')) {
    const cols = MQ3.matches ? 3 : MQ2.matches ? 2 : 1;
    const board = $('#board');
    board.dataset.cols = String(cols);
    const weights = tables.map((t) => +t.dataset.weight);
    const total = weights.reduce((a, b) => a + b, 0);
    const groups = Array.from({ length: cols }, () => []);
    let g = 0, acc = 0;
    tables.forEach((t, i) => {
      const remainingCols = cols - g - 1;
      const target = (total / cols) * (g + 1);
      if (g < cols - 1 && acc > 0 && acc + weights[i] / 2 > target && tables.length - i > remainingCols - 1) g++;
      groups[g].push(t); acc += weights[i];
    });
    const frag = document.createDocumentFragment();
    groups.forEach((grp) => { const col = document.createElement('div'); col.className = 'cnry-col'; grp.forEach((t) => col.appendChild(t)); frag.appendChild(col); });
    board.replaceChildren(frag);
  }

  function detailHTML(id) {
    const s = D.cat.signals.find((x) => x.id === id);
    const c = D.status.signals[id];
    const st = effective(s);
    const dom = D.cat.domains.find((d) => d.id === s.domain);
    const sp = c ? seriesFor(s) : null;
    const hist = (D.history[id] || []).slice(-60);
    const tag = (t, kind = 'gray') => `<span class="cds--tag cds--tag--${kind} cds--tag--sm"><span class="cds--tag__label">${esc(t)}</span></span>`;
    const left = [];
    if (c) {
      left.push(`<div class="cnry-detail__lead">${statusIndicator(st)}${trendCell(c.trend)}${c.value ? `<span class="cnry-reading">${esc(c.value)}</span>` : ''}</div>`);
      left.push(`<p class="cnry-detail__summary">${esc(c.summary)}</p>`);
      left.push(`<div class="cnry-detail__block"><h3>Why it's at this level</h3><p>${esc(c.state)}</p></div>`);
      left.push(`<div class="cnry-detail__block"><h3>What this means for you</h3><p>${esc(c.for_you)}</p></div>`);
    } else {
      left.push('<p class="cnry-detail__summary">This signal has not been assessed yet.</p>');
    }
    left.push(`<div class="cnry-detail__block cnry-detail__muted"><h3>Why it matters</h3><p>${esc(s.why)}</p></div>`);
    left.push(`<div class="cnry-detail__block cnry-detail__muted"><h3>What moves it</h3><p>${esc(s.drivers)}</p></div>`);
    const horizon = { chronic: 'Chronic', seasonal: 'Seasonal' }[s.horizon];
    left.push(`<div class="cnry-detail__meta">${tag(dom?.name || '', 'cool-gray')}${tag(s.tier === 'daily' ? 'Checked daily' : 'Checked every run')}${horizon ? tag(horizon, 'warm-gray') : ''}${c ? `<span class="cnry-meta-text">Checked ${esc(fmtUK.format(new Date(c.checked_at)))}. At this level since ${esc(fmtUK.format(new Date(c.changed_at)))}.</span>` : ''}</div>`);
    left.push(`<p class="cnry-meta-text cnry-permalinks"><a class="cds--link cds--link--sm" href="/s/${s.id}">Permalink</a> · <a class="cds--link cds--link--sm" href="/s/${s.id}.md">Markdown</a> · <a class="cds--link cds--link--sm" href="/s/${s.id}.json">JSON</a></p>`);
    if (c?.override_reason) left.push(`<p class="cnry-meta-text">Assessor note: ${esc(c.override_reason)}</p>`);

    const right = [];
    if (sp) right.push(chartSVG(sp));
    if (hist.length > 1) {
      right.push(`<div class="cnry-detail__block"><h3>Status at each of the last ${hist.length} checks</h3><div class="cnry-hist" role="img" aria-label="Status history">${hist.map((p) => `<i class="${p[1]}" title="${esc(fmtUK.format(new Date(p[0])))}"></i>`).join('')}</div></div>`);
    }
    const hit = c && c.rubric_hit && c.rubric_hit !== s.rubric[c.status] ? `<p class="cnry-meta-text cnry-rubric-hit">Rated on: ${esc(c.rubric_hit)}</p>` : '';
    right.push(`<div class="cnry-detail__block"><h3>How it's rated</h3>${hit}
      <div class="cds--structured-list cds--structured-list--condensed cds--structured-list--flush" role="table" aria-label="Rating criteria">
        <div class="cds--structured-list-tbody" role="rowgroup">
          ${['red', 'amber', 'green'].map((k) => `<div class="cds--structured-list-row${c && c.status === k ? ' is-current' : ''}" role="row">
            <div class="cds--structured-list-td" role="cell"><span class="cnry-rubric-level">${statusIcon(k)}${LABEL[k]}</span></div>
            <div class="cds--structured-list-td" role="cell">${esc(s.rubric[k])}</div></div>`).join('')}
        </div></div></div>`);
    if (c?.sources?.length) {
      right.push(`<div class="cnry-detail__block"><h3>Sources</h3><ul class="cnry-sources">${c.sources.map((x) =>
        `<li><a class="cds--link cds--link--sm" href="${esc(x.url)}" target="_blank" rel="noopener nofollow">${esc(x.title)}<span class="cds--link__icon">${icon('launch')}</span></a>${x.date ? `<span class="cnry-src-date">${esc(fmtDate.format(new Date(x.date)))}</span>` : ''}</li>`).join('')}</ul></div>`);
    }
    return `<div class="cnry-detail"><div>${left.join('')}</div><div>${right.join('')}</div></div>`;
  }

  // Keep child-row colspan equal to the visible column count (columns hide at small breakpoints)
  function syncColspans() {
    $$('.cnry-dt').forEach((t) => {
      const first = t.querySelector('tr[data-parent-row]');
      const n = first ? [...first.children].filter((td) => getComputedStyle(td).display !== 'none').length : COLS;
      $$('tr[data-child-row] > td', t).forEach((td) => { td.colSpan = n; });
    });
  }

  function setExpanded(row, open) {
    const child = row.nextElementSibling;
    const btn = row.querySelector('.cds--table-expand__button');
    const cell = row.querySelector('td.cds--table-expand');
    if (open) {
      const inner = child.querySelector('.cds--child-row-inner-container');
      if (!inner.dataset.filled) { inner.innerHTML = detailHTML(row.dataset.id); inner.dataset.filled = '1'; }
      row.classList.add('cds--expandable-row');
      cell.setAttribute('data-previous-value', 'collapsed');
      child.hidden = row.hidden;
    } else {
      row.classList.remove('cds--expandable-row');
      cell.removeAttribute('data-previous-value');
      child.hidden = true;
    }
    btn.setAttribute('aria-expanded', String(open));
  }

  function goTo(id, push = true) {
    const row = document.getElementById(id);
    if (!row || !row.matches('tr[data-parent-row]')) return;
    if (row.closest('[hidden]') || row.hidden) { setStatus('all'); setText(''); }
    setExpanded(row, true);
    row.scrollIntoView({ block: 'start', behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
    row.querySelector('.cds--table-expand__button').focus({ preventScroll: true });
    if (push && location.hash !== `#${id}`) history.pushState(null, '', `#${id}`);
  }

  // ───────── Filtering ─────────
  function applyFilter() {
    const q = state.text.trim().toLowerCase();
    let shown = 0;
    $$('.cnry-domain-table').forEach((tbl) => {
      let vis = 0;
      $$('tr[data-parent-row]', tbl).forEach((row) => {
        const id = row.dataset.id;
        const s = D.cat.signals.find((x) => x.id === id);
        const c = D.status.signals[id] || {};
        const okStatus = state.status === 'all' || row.dataset.st === state.status;
        const hay = `${s.name} ${c.value || ''} ${c.summary || ''} ${c.state || ''}`.toLowerCase();
        const ok = okStatus && (!q || hay.includes(q));
        row.hidden = !ok; row.nextElementSibling.hidden = !ok || !row.classList.contains('cds--expandable-row');
        if (ok) vis++;
      });
      tbl.hidden = vis === 0;
      shown += vis;
    });
    $('#empty').hidden = shown > 0;
    $$('.cnry-kpi--count').forEach((t) => t.classList.toggle('is-active', t.dataset.filter === state.status));
  }
  function setStatus(st) {
    state.status = st;
    $$('#status-switcher .cds--content-switcher-btn').forEach((b) => {
      const on = b.dataset.status === st;
      b.classList.toggle('cds--content-switcher--selected', on);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
    });
    applyFilter();
  }
  function setText(v) {
    state.text = v;
    $('#filter-text').value = v;
    $('#filter-clear').classList.toggle('cds--search-close--hidden', !v);
    applyFilter();
  }

  // ───────── Theme ─────────
  function currentTheme() {
    return document.documentElement.getAttribute('data-theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  }
  function syncThemeButton() {
    const btn = $('#theme-toggle');
    const dark = currentTheme() === 'dark';
    btn.innerHTML = icon(dark ? 'light' : 'asleep');
    btn.setAttribute('aria-label', dark ? 'Switch to light theme' : 'Switch to dark theme');
  }

  function wire() {
    $('#theme-toggle').addEventListener('click', () => {
      const next = currentTheme() === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next);
      store.set('canary.theme', next);
      syncThemeButton();
    });
    $('#board').addEventListener('click', (e) => {
      const row = e.target.closest('tr[data-parent-row]');
      if (!row || e.target.closest('a')) return;
      const open = !row.classList.contains('cds--expandable-row');
      setExpanded(row, open);
      if (open && location.hash !== `#${row.id}`) history.replaceState(null, '', `#${row.id}`);
    });
    document.addEventListener('click', (e) => {
      const a = e.target.closest('[data-goto]');
      if (a) { e.preventDefault(); goTo(a.dataset.goto); }
    });
    $('#status-switcher').addEventListener('click', (e) => {
      const b = e.target.closest('.cds--content-switcher-btn');
      if (b) setStatus(b.dataset.status);
    });
    $('#status-switcher').addEventListener('keydown', (e) => {
      if (!['ArrowLeft', 'ArrowRight'].includes(e.key)) return;
      const btns = $$('#status-switcher .cds--content-switcher-btn');
      const i = btns.findIndex((b) => b.dataset.status === state.status);
      const n = btns[(i + (e.key === 'ArrowRight' ? 1 : btns.length - 1)) % btns.length];
      setStatus(n.dataset.status); n.focus();
    });
    $$('.cnry-kpi--count').forEach((t) => t.addEventListener('click', () => {
      setStatus(state.status === t.dataset.filter ? 'all' : t.dataset.filter);
      $('.cnry-signals').scrollIntoView({ behavior: 'smooth', block: 'start' });
    }));
    let timer;
    $('#filter-text').addEventListener('input', (e) => { clearTimeout(timer); timer = setTimeout(() => setText(e.target.value), 120); });
    $('#filter-text').addEventListener('keydown', (e) => { if (e.key === 'Escape') setText(''); });
    $('#filter-clear').addEventListener('click', () => { setText(''); $('#filter-text').focus(); });
    $('#expand-all').addEventListener('click', (e) => {
      const rows = $$('#board tr[data-parent-row]:not([hidden])');
      const open = rows.some((r) => !r.classList.contains('cds--expandable-row'));
      rows.forEach((r) => setExpanded(r, open));
      e.currentTarget.querySelector('span').textContent = open ? 'Collapse all' : 'Expand all';
    });
    window.addEventListener('popstate', () => { const id = location.hash.slice(1); if (id) goTo(id, false); });
  }

  async function init() {
    hydrateIcons();
    syncThemeButton();
    try {
      const [cat, status, metrics, hist, changes] = await Promise.all([
        getJSON('catalogue.json'), getJSON('status.json', { signals: {} }), getJSON('metrics.json', { metrics: {} }),
        getJSON('history.json', {}), getJSON('changes.json', []),
      ]);
      D = { cat, status: { signals: {}, ...status }, metrics: metrics.metrics || {}, history: hist, changes };
      renderSummary(); renderDomains(); renderLegend(); renderChanges(); renderBoard(); wire(); setStatus('all');
      [MQ2, MQ3].forEach((q) => q.addEventListener('change', () => layoutBoard()));
      const id = location.hash.slice(1);
      if (id && document.getElementById(id)?.matches('tr')) goTo(id, false);
    } catch (e) {
      $('#error-text').textContent = "Canary couldn't load its latest data, so the board below may be out of date. Refresh the page; if this persists, an update may still be deploying.";
      $('#error').hidden = false;
      console.error(e);
    }
  }
  init();
})();
