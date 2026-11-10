'use strict';
/* AI Battle Royale report. Works from file:// with no server. Data: window.BR (app/data.js). */
const D = window.BR;
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const V = new Map(D.videos.map(v => [v.id, v]));
const M = Object.fromEntries(D.models.map(m => [m.id, m]));
const ORDER = D.models.map(m => m.id);
const NOTES = new Map();
for (const t of D.review.topics) for (const m of t.models) for (const o of m.observations) NOTES.set(o.id, { ...o, model: m.model, topic: t.id, topicTitle: t.title });
const TONE = { positive: ['+', 'Good'], mixed: ['~', 'Mixed'], negative: ['−', 'Weak'], neutral: ['·', 'Neutral'] };
const clock = n => { n = Math.round(n || 0); return Math.floor(n / 60) + ':' + String(n % 60).padStart(2, '0'); };
const clock10 = n => { const t = Math.round(Number(n) * 10), w = Math.floor(t / 10); return Math.floor(w / 60) + ':' + String(w % 60).padStart(2, '0') + (t % 10 ? '.' + t % 10 : ''); };
const money = n => '$' + Number(n).toFixed(2);
const money0 = n => '$' + Math.round(n);
const hours = s => (s / 3600).toFixed(1) + ' h';
const millions = n => { if (n < 1e5) return (n / 1e3).toFixed(1) + ' K'; const m = n / 1e6; return (m >= 100 ? Math.round(m) : m.toFixed(1)) + ' M'; };
const hm = s => { const m = Math.round(s / 60); return Math.floor(m / 60) + 'h ' + String(m % 60).padStart(2, '0') + 'm'; };
const dot = () => '<span class="dot"></span>';
const tone = t => `<span class="tone ${esc(t)}" aria-label="${esc((TONE[t] || TONE.neutral)[1])}">${esc((TONE[t] || TONE.neutral)[0])}</span>`;
const scope = (id, stage) => D.costs.comparison.models.find(m => m.id === id).scopes[stage];

/* ---------- cards ---------- */
function vcard(v, o = {}) {
  if (!v) return '';
  const label = o.title ?? v.title;
  const head = `<div class="head">${dot()}${esc(M[v.model].name)}<span class="t">${v.duration ? clock(v.duration) : ''}</span></div>`;
  const thumb = `<button class="thumb${o.square ? ' square' : ''}" data-open="${esc(v.id)}" ${o.hover ? `data-hover="${esc(v.path)}"` : ''} aria-label="Watch ${esc(M[v.model].name + ', ' + label)}"><img src="${esc(v.poster)}" alt="" loading="lazy" decoding="async"><span class="play" aria-hidden="true">▶</span></button>`;
  const body = [];
  if (o.select) body.push(o.select);
  if (o.badge) body.push(`<div>${o.badge}</div>`);
  if (!o.noTitle) body.push(`<h4>${esc(label)}</h4>`);
  if (o.text) body.push(`<p>${esc(o.text)}</p>`);
  if (o.stats) body.push(`<div class="stats">${o.stats}</div>`);
  if (o.notes?.length) body.push(notesList(o.notes));
  if (v.blendUri && o.blend !== false) body.push(`<a class="blend" href="${esc(v.blendUri)}" download>Download .blend ↓</a>`);
  return `<article class="vcard" data-m="${esc(v.model)}" data-card="${esc(v.id)}">${head}${thumb}${body.length ? `<div class="body">${body.join('')}</div>` : ''}</article>`;
}
function notesList(list) {
  return `<ul class="notes">${list.map(n => `<li>${tone(n.tone)}<button data-note="${esc(n.id)}" title="Play ${esc(clock10(n.start))} to ${esc(clock10(n.end))}">${esc(n.text)}</button></li>`).join('')}</ul>`;
}
function shot(id) {
  const n = NOTES.get(id);
  if (!n) return '';
  return `<button class="shot" data-m="${esc(n.model)}" data-note="${esc(id)}" aria-label="Play ${esc(M[n.model].name + ': ' + n.title)}"><img src="${esc(n.screenshot.uri)}" alt="" loading="lazy" decoding="async"><span class="cap"><b>${dot()}${esc(M[n.model].name)} ${tone(n.tone)}</b>${esc(n.text)}</span></button>`;
}
function moment(m) {
  const cols = m.notes.length >= 4 ? 'row4' : m.notes.length === 3 ? 'row3' : 'row2';
  return `<section class="moment" id="${esc(m.id)}"><div class="moment-head"><div><h4>${esc(m.title)}</h4><p>${esc(m.text)}</p></div><button class="btn" data-compare-notes="${esc(m.notes.join(','))}">▶ Play side by side</button></div><div class="${cols}">${m.notes.map(shot).join('')}</div></section>`;
}
function renderMoments(sel, list) { const el = $(sel); if (el) el.innerHTML = list.map(moment).join(''); }

/* ---------- filter ---------- */
function filterBar(sel) {
  const el = $(sel);
  if (!el) return;
  el.innerHTML = `<button class="chip" data-filter="" aria-pressed="true">All four</button>` + D.models.map(m => `<button class="chip" data-m="${m.id}" data-filter="${m.id}" aria-pressed="false">${dot()}${esc(m.name)}</button>`).join('');
  el.addEventListener('click', e => {
    const b = e.target.closest('[data-filter]');
    if (!b) return;
    $$('[data-filter]', el).forEach(x => x.setAttribute('aria-pressed', String(x === b)));
    if (b.dataset.filter) document.body.dataset.filter = b.dataset.filter; else delete document.body.dataset.filter;
  });
}

/* ---------- viewer ---------- */
let cleanup = null;
const dlg = () => $('#viewer');
function closeViewer() {
  if (cleanup) { cleanup(); cleanup = null; }
  const d = dlg();
  if (!d) return;
  $$('video', d).forEach(v => { v.pause(); v.removeAttribute('src'); v.load(); });
  $('.dlg-body', d).replaceChildren();
  if (d.open) d.close();
}
function showViewer(titleHtml, bodyHtml, model) {
  closeViewer();
  const d = dlg();
  d.dataset.m = model || '';
  $('.dlg-head h2', d).innerHTML = titleHtml;
  $('.dlg-body', d).innerHTML = bodyHtml;
  d.showModal();
}
function openVideo(id, at) {
  const v = V.get(id);
  if (!v) return;
  const chapters = v.chapters?.length ? `<div class="chapters">${v.chapters.map(c => `<button data-seek="${Number(c.start)}"><time>${clock(c.start)}</time><span>${esc(c.title)}</span></button>`).join('')}</div>` : '';
  const details = !chapters && v.details?.length ? `<ul>${v.details.map(t => `<li>${esc(t)}</li>`).join('')}</ul>` : '';
  const hand = D.hand[v.id];
  const body = `<video controls playsinline preload="metadata" src="${esc(v.path)}" poster="${esc(v.poster)}"></video><div class="dlg-copy">`
    + (hand ? `<p><span class="badge hand">Played by hand</span> Recorded ${esc(hand.when)}. ${esc(hand.text)}</p>` : '')
    + (v.description ? `<p>${esc(v.description)}</p>` : '') + chapters + details
    + (v.note ? `<p class="small">${esc(v.note)}</p>` : '') + (v.metrics ? `<p class="small">${esc(v.metrics)}</p>` : '')
    + (v.sectionNote ? `<p class="small">${esc(v.sectionNote)}</p>` : '')
    + `<div class="dlg-links"><a class="btn" href="${esc(v.path)}" download>Download video ↓</a>${v.blendUri ? `<a class="btn" href="${esc(v.blendUri)}" download>Download .blend ↓</a>` : ''}</div></div>`;
  showViewer(`${dot()}${esc(M[v.model].name)}: ${esc(hand ? hand.title : (v.variant && v.kind === 'assets' ? v.title + ', ' + v.variant : v.title))}`, body, v.model);
  const player = $('video', dlg());
  if (at) player.addEventListener('loadedmetadata', () => { player.currentTime = at; player.play().catch(() => {}); }, { once: true });
}
function openExcerpt(id) {
  const n = NOTES.get(id);
  if (!n) return;
  const v = V.get(n.videoId);
  if (!v) return;
  const body = `<video controls playsinline preload="auto" src="${esc(v.path)}" poster="${esc(n.screenshot.uri)}"></video><div class="dlg-copy"><p>${tone(n.tone)} ${esc(n.text)}</p><div class="dlg-links"><button class="btn" id="replay">↻ Replay ${esc(clock10(n.start))} to ${esc(clock10(n.end))}</button><button class="btn ghost" id="full">Open the full recording</button><button class="btn ghost" data-zoom-src="${esc(n.screenshot.uri)}">Screenshot</button><span class="small" id="status" role="status"></span></div></div>`;
  showViewer(`${dot()}${esc(M[n.model].name)}: ${esc(n.title)}`, body, n.model);
  const p = $('video', dlg());
  let stopped = false;
  const play = () => { stopped = false; $('#status').textContent = ''; p.currentTime = n.start; p.play().catch(() => { $('#status').textContent = 'Press play to start'; }); };
  const check = () => { if (!stopped && !p.paused && p.currentTime >= n.end - 0.02) { stopped = true; p.pause(); $('#status').textContent = 'Excerpt finished'; } };
  p.addEventListener('loadedmetadata', play, { once: true });
  p.addEventListener('timeupdate', check);
  const timer = setInterval(check, 40);
  cleanup = () => clearInterval(timer);
  $('#replay').onclick = play;
  $('#full').onclick = () => openVideo(v.id);
}
/* items: [{id, start, end, label}] */
function openCompare(items, title) {
  const body = `<div class="compare${items.length === 1 ? ' one' : ''}">${items.map((it, i) => { const v = V.get(it.id); return `<figure data-m="${esc(v.model)}"><figcaption>${dot()}${esc(it.label || M[v.model].name)}</figcaption><video data-i="${i}" controls muted playsinline preload="metadata" src="${esc(v.path)}" poster="${esc(it.poster || v.poster)}"></video></figure>`; }).join('')}</div><div class="compare-bar"><button class="btn" id="cmp-play">▶ Play all</button><button class="btn ghost" id="cmp-pause">Pause</button><button class="btn ghost" id="cmp-reset">↻ Back to start</button><span>All muted. Unmute one player to hear it.</span></div>`;
  showViewer(esc(title || 'Side by side'), body);
  const vids = $$('video', dlg());
  const start = i => items[i].start || 0;
  const seek = () => vids.forEach((p, i) => { try { p.currentTime = start(i); } catch {} });
  vids.forEach((p, i) => p.addEventListener('loadedmetadata', () => { if (start(i)) p.currentTime = start(i); }, { once: true }));
  const check = () => vids.forEach((p, i) => { if (items[i].end && !p.paused && p.currentTime >= items[i].end - 0.02) p.pause(); });
  const timer = setInterval(check, 60);
  cleanup = () => clearInterval(timer);
  $('#cmp-play').onclick = () => { vids.forEach((p, i) => { if (items[i].end && p.currentTime >= items[i].end - 0.05) p.currentTime = start(i); p.play().catch(() => {}); }); };
  $('#cmp-pause').onclick = () => vids.forEach(p => p.pause());
  $('#cmp-reset').onclick = () => { vids.forEach(p => p.pause()); seek(); };
}
function openImage(src, title) {
  showViewer(esc(title || 'Image'), `<img class="full" src="${esc(src)}" alt=""><div class="dlg-copy dlg-links"><a class="btn" href="${esc(src)}" download>Download ↓</a></div>`);
}

/* ---------- global clicks ---------- */
document.addEventListener('click', e => {
  const c = e.target.closest('[data-open],[data-note],[data-compare],[data-compare-notes],[data-seek],[data-zoom-src],img[data-zoom],[data-close]');
  if (!c) return;
  if (c.dataset.close !== undefined) { closeViewer(); return; }
  if (c.dataset.open) { e.preventDefault(); openVideo(c.dataset.open); return; }
  if (c.dataset.note) { e.preventDefault(); openExcerpt(c.dataset.note); return; }
  if (c.dataset.compare) {
    const ids = c.dataset.compare.split(',');
    openCompare(ids.map(id => ({ id })), c.dataset.title);
    return;
  }
  if (c.dataset.compareNotes) {
    const items = c.dataset.compareNotes.split(',').map(id => { const n = NOTES.get(id); return { id: n.videoId, start: n.start, end: n.end, label: M[n.model].name + ': ' + n.title, poster: n.screenshot.uri }; });
    openCompare(items, c.closest('.moment')?.querySelector('h4')?.textContent);
    return;
  }
  if (c.dataset.seek) { const p = $('video', dlg()); if (p) { p.currentTime = Number(c.dataset.seek); p.play().catch(() => {}); } return; }
  if (c.dataset.zoomSrc) { openImage(c.dataset.zoomSrc); return; }
  if (c.matches('img[data-zoom]')) openImage(c.currentSrc || c.src, c.alt);
});
document.addEventListener('DOMContentLoaded', () => {
  const d = dlg();
  if (d) {
    d.addEventListener('cancel', e => { e.preventDefault(); closeViewer(); });
    d.addEventListener('click', e => { if (e.target === d) closeViewer(); });
  }
});
/* turntable preview on hover */
document.addEventListener('mouseover', e => {
  const t = e.target.closest?.('.thumb[data-hover]');
  if (!t || t.dataset.live) return;
  t.dataset.live = '1';
  t._timer = setTimeout(() => {
    const v = document.createElement('video');
    v.src = t.dataset.hover; v.muted = true; v.loop = true; v.playsInline = true; v.autoplay = true;
    t.append(v);
    v.play().catch(() => {});
  }, 140);
});
document.addEventListener('mouseout', e => {
  const t = e.target.closest?.('.thumb[data-hover]');
  if (!t || (e.relatedTarget && t.contains(e.relatedTarget))) return;
  clearTimeout(t._timer);
  delete t.dataset.live;
  $$('video', t).forEach(v => { v.pause(); v.removeAttribute('src'); v.load(); v.remove(); });
});
/* tooltip */
let tipEl = null;
document.addEventListener('mousemove', e => {
  const t = e.target.closest?.('[data-tip]');
  if (!t) { if (tipEl) { tipEl.remove(); tipEl = null; } return; }
  if (!tipEl) { tipEl = document.createElement('div'); tipEl.className = 'tip'; document.body.append(tipEl); }
  tipEl.textContent = t.dataset.tip;
  const r = tipEl.getBoundingClientRect();
  tipEl.style.left = Math.min(innerWidth - r.width - 8, e.clientX + 14) + 'px';
  tipEl.style.top = Math.min(innerHeight - r.height - 8, e.clientY + 14) + 'px';
});

/* ---------- charts ---------- */
function bars(rows, fmt, max) {
  const top = max || Math.max(...rows.map(r => r.value));
  return `<div class="bars">${rows.map(r => `<div class="bar-row" data-m="${esc(r.id)}"><div class="name">${esc(r.name || M[r.id].short)}${dot()}</div><div class="bar-track"><div class="bar-fill" style="width:${Math.max(0.4, r.value / top * 100).toFixed(2)}%" data-tip="${esc(M[r.id].name + ': ' + (r.tip || fmt(r.value)))}"></div></div><div class="val">${esc(fmt(r.value))}</div></div>`).join('')}</div>`;
}
function legend() { return `<div class="legend">${D.models.map(m => `<span data-m="${m.id}">${dot()}${esc(m.name)}</span>`).join('')}</div>`; }
function stagePanel(title, hint, stage, field, fmt) {
  const rows = ORDER.map(id => ({ id, value: scope(id, stage)[field] }));
  return `<div class="panel"><h4>${esc(title)}</h4>${hint ? `<p class="hint">${esc(hint)}</p>` : ''}${bars(rows, fmt)}</div>`;
}
function stageTiles(stage) {
  return `<div class="row4">${D.costs.comparison.models.map(m => {
    const s = m.scopes[stage];
    return `<div class="tile top" data-m="${m.id}"><div class="who">${dot()}${esc(m.name)}</div><div class="v">≈ ${money(s.usd)}</div><div class="l">${esc(hm(s.active_seconds))} active, ${esc(millions(s.tokens_total))} tokens on this stage</div></div>`;
  }).join('')}</div>`;
}

/* ---------- pages ---------- */
const PAGES = {};

PAGES.setup = () => {
  const over = (a, m) => D.videos.find(v => v.kind === 'assets' && v.asset === a && v.model === m && v.isOverview) || D.videos.find(v => v.kind === 'assets' && v.asset === a && v.model === m);
  const mini = (fn) => `<div class="mini4">${ORDER.map(m => { const v = fn(m); return `<img data-m="${m}" src="${esc(v.poster)}" alt="${esc(M[m].name)}" loading="lazy">`; }).join('')}</div>`;
  $('#mini-assets').innerHTML = mini(m => over('treasure_chest', m));
  $('#mini-map').innerHTML = mini(m => D.videos.find(v => v.kind === 'maps' && v.model === m));
  $('#mini-game').innerHTML = mini(m => V.get(D.scenarios.find(s => s.id === 'match').selected[m]));
};

PAGES.assets = () => {
  filterBar('#filter');
  $('#stage-tiles').innerHTML = stageTiles('assets');
  renderMoments('#moments', D.moments.assets);
  const groups = [...new Set(D.assets.map(a => a.group))];
  const chips = $('#groups');
  chips.innerHTML = `<button class="chip" data-g="" aria-pressed="true">All 21 sets</button>` + groups.map(g => `<button class="chip" data-g="${esc(g)}" aria-pressed="false">${esc(g)}</button>`).join('');
  const chosen = new Map();
  const stats = (asset, m) => {
    const s = D.assetStats[asset][m];
    if (!s) return '';
    return `<span><b>${s.tris ? s.tris.toLocaleString('en-US') : '?'}</b> tris</span><span><b>${money(s.usd)}</b></span><span><b>${esc(hm(s.seconds))}</b></span>`;
  };
  const card = (a, m) => {
    const opts = D.videos.filter(v => v.kind === 'assets' && v.asset === a.id && v.model === m);
    const v = opts.find(x => x.id === chosen.get(a.id + m)) || opts.find(x => x.isOverview) || opts[0];
    const select = opts.length > 1 ? `<select data-variant="${esc(a.id + '|' + m)}" aria-label="${esc(M[m].name + ' ' + a.title)} view">${opts.map(o => `<option value="${esc(o.id)}"${o.id === v.id ? ' selected' : ''}>${esc(o.variant || o.title)}</option>`).join('')}</select>` : '';
    return vcard(v, { square: true, hover: true, noTitle: true, select, stats: stats(a.id, m), text: v.metrics?.startsWith('Rendered from') ? 'Rendered from the .blend: the .glb export lost the material colors.' : '' });
  };
  const render = () => {
    const g = $('[data-g][aria-pressed=true]', chips).dataset.g;
    $('#asset-rows').innerHTML = D.assets.filter(a => !g || a.group === g).map(a => {
      const allIds = ORDER.map(m => (D.videos.find(v => v.kind === 'assets' && v.asset === a.id && v.model === m && v.isOverview) || {}).id).filter(Boolean).join(',');
      return `<section class="topic" id="asset-${esc(a.id)}"><div class="topic-head"><div><h3>${esc(a.title)}</h3><p>${esc(a.group)}. ${esc(a.size || '')} Budget: ${esc(a.budget || 'n/a')}</p></div><button class="btn" data-compare="${esc(allIds)}" data-title="${esc(a.title)}, all four">▶ Compare all four</button></div><div class="row5"><article class="vcard refcard"><div class="head">Reference</div><div class="thumb square contain"><img data-zoom src="${esc(a.refs[0])}" alt="${esc(a.title)} reference" loading="lazy" style="cursor:zoom-in"></div></article>${ORDER.map(m => card(a, m)).join('')}</div></section>`;
    }).join('');
  };
  chips.addEventListener('click', e => { const b = e.target.closest('[data-g]'); if (!b) return; $$('[data-g]', chips).forEach(x => x.setAttribute('aria-pressed', String(x === b))); render(); });
  document.addEventListener('change', e => { const k = e.target.dataset?.variant; if (!k) return; const [a, m] = k.split('|'); chosen.set(a + m, e.target.value); render(); });
  render();
  // cost grid: one hue, sequential by asset cost
  const max = Math.max(...D.assets.flatMap(a => ORDER.map(m => D.assetStats[a.id][m]?.usd || 0)));
  const sorted = [...D.assets].sort((a, b) => ORDER.reduce((s, m) => s + (D.assetStats[b.id][m]?.usd || 0), 0) - ORDER.reduce((s, m) => s + (D.assetStats[a.id][m]?.usd || 0), 0));
  $('#heat').innerHTML = `<table class="heat"><thead><tr><th>Asset set</th>${D.models.map(m => `<th>${esc(m.short)}</th>`).join('')}</tr></thead><tbody>${sorted.map(a => `<tr><th><a href="#asset-${esc(a.id)}">${esc(a.title)}</a></th>${ORDER.map(m => { const s = D.assetStats[a.id][m]; const c = s ? s.usd / max : 0; return `<td style="background:rgba(80,141,232,${(0.06 + c * 0.72).toFixed(3)})" data-tip="${esc(M[m].name + ', ' + a.title + ': ' + (s ? money(s.usd) + ', ' + hm(s.seconds) + ', ' + s.tokens.toLocaleString('en-US') + ' tokens' : ''))}">${s ? money(s.usd) : ''}</td>`; }).join('')}</tr>`).join('')}</tbody></table>`;
};

PAGES.map = () => {
  $('#stage-tiles').innerHTML = stageTiles('map');
  const maps = kind => D.videos.filter(v => v.kind === 'maps' && v.title.includes(kind));
  const row = (kind, title) => {
    const list = maps(kind);
    return `<section class="topic"><div class="topic-head"><div><h3>${esc(title)}</h3></div><button class="btn" data-compare="${esc(list.map(v => v.id).join(','))}" data-title="Islands, ${esc(kind.toLowerCase())}">▶ Play all four together</button></div><div class="row4">${list.map(v => vcard(v, { noTitle: true, blend: false })).join('')}</div></section>`;
  };
  $('#islands').innerHTML = row('Orbit', 'Orbit') + row('Flythrough', 'Flythrough');
  renderMoments('#moments', D.moments.map);
  const t = D.review.topics.find(x => x.id === 'island');
  $('#island-notes').innerHTML = `<div class="row4">${ORDER.map(m => { const list = t.models.find(x => x.model === m).observations.map(o => NOTES.get(o.id)); return `<div class="panel" data-m="${m}"><h4 style="display:flex;gap:7px;align-items:center;margin-bottom:8px">${dot()}${esc(M[m].name)}</h4>${notesList(list)}<p></p></div>`; }).join('')}</div>`;
};

PAGES.gameplay = () => {
  filterBar('#filter');
  $('#stage-tiles').innerHTML = stageTiles('remainder');
  // pinned: hand-played
  $('#hand').innerHTML = `<div class="row4">${D.handOrder.map(id => { const v = V.get(id), h = D.hand[id]; return vcard(v, { title: h.title, text: h.text, blend: false }); }).join('')}</div>`;
  // pinned: full matches
  const matches = D.scenarios.find(s => s.id === 'match').selected;
  $('#matches').innerHTML = `<div class="row4">${ORDER.map(m => vcard(V.get(matches[m]), { title: D.matchNotes[m].title, text: D.matchNotes[m].text, blend: false })).join('')}</div>`;
  renderMoments('#moments', D.moments.gameplay);
  // Gemini before/after
  const g = D.geminiStaged;
  $('#staged').innerHTML = `<div class="row2">${vcard(V.get(g.before), { title: 'Before the rework: staged', text: V.get(g.before).description, blend: false })}${vcard(V.get(g.after), { title: 'After the rework: played by the autopilot', text: V.get(g.after).description, blend: false })}</div>`;
  // mechanics rows
  const reviewFor = { deployment: 'deployment', 'movement-complete': 'movement', 'weapons-complete': 'weapons', 'building-complete': 'building', 'harvesting-complete': 'harvesting', 'traversal-complete': 'traversal', 'results-complete': 'results' };
  let last = '';
  $('#mechanics').innerHTML = D.topics.map(t => {
    const rv = D.review.topics.find(x => x.id === reviewFor[t.id]);
    const ids = ORDER.map(m => t.models[m]?.video).filter(Boolean);
    const groupLabel = t.group !== last ? `<div class="group-label">${esc(t.group)}</div>` : '';
    last = t.group;
    const cards = ORDER.map(m => {
      const v = V.get(t.models[m]?.video);
      const notes = rv ? rv.models.find(x => x.model === m).observations.map(o => NOTES.get(o.id)) : [];
      return vcard(v, { noTitle: true, notes, blend: false });
    }).join('');
    return `${groupLabel}<section class="topic" id="t-${esc(reviewFor[t.id] || t.id)}"><div class="topic-head"><div><h3>${esc(t.title)}</h3><p>${esc(t.details)}</p></div><button class="btn" data-compare="${esc(ids.join(','))}" data-title="${esc(t.title)}">▶ Compare all four</button></div><div class="row4">${cards}</div></section>`;
  }).join('');
  // showcases
  $('#showcases').innerHTML = D.scenarios.filter(s => s.id !== 'match').map(s => {
    const ids = ORDER.map(m => s.selected[m]).filter(Boolean);
    return `<section class="topic"><div class="topic-head"><div><h3>${esc(s.title)}</h3><p>${esc(s.description)}</p></div><button class="btn" data-compare="${esc(ids.join(','))}" data-title="${esc(s.title)}">▶ Compare all four</button></div><div class="row4">${ids.map(id => vcard(V.get(id), { blend: false })).join('')}</div></section>`;
  }).join('');
  // archive: rendered when opened
  const arch = $('#archive');
  const pinned = new Set([...D.handOrder, ...Object.values(matches), g.before, g.after, ...D.topics.flatMap(t => Object.values(t.models).map(x => x.video)), ...D.scenarios.flatMap(s => Object.values(s.selected))]);
  const rest = D.videos.filter(v => ['archive', 'mechanics'].includes(v.kind) && !pinned.has(v.id));
  $('#archive-count').textContent = rest.length;
  let drawn = false;
  const draw = () => {
    const q = ($('#q').value || '').toLowerCase().trim();
    const list = rest.filter(v => !q || [v.title, v.description, v.note, v.section, v.sectionNote, M[v.model].name].join(' ').toLowerCase().includes(q));
    $('#archive-grid').innerHTML = `<div class="row4">${list.map(v => vcard(v, { text: v.description, blend: false, badge: v.section ? `<span class="badge">${esc(v.section)}</span>` : '' })).join('')}</div>`;
    $('#archive-found').textContent = list.length + ' recordings';
  };
  arch.addEventListener('toggle', () => { if (arch.open && !drawn) { drawn = true; draw(); } });
  let timer;
  $('#q').addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(draw, 150); });
};

PAGES.verdict = () => {
  $('#ranks').innerHTML = D.verdict.map((r, i) => `<div class="rank" data-m="${r.id}"><div class="pos">${i + 1}</div><div class="name">${dot()}${esc(M[r.id].name)}</div><p>${esc(r.text)}</p></div>`).join('');
  const topicLink = id => (id === 'island' ? 'map.html#island-notes' : 'gameplay.html#t-' + id);
  const rows = D.review.topics.map(t => `<tr><th><a href="${topicLink(t.id)}">${esc(t.title)}</a></th>${ORDER.map(m => { const obs = t.models.find(x => x.model === m).observations; return `<td><div class="squares" data-m="${m}">${obs.map(o => `<button data-note="${esc(o.id)}" data-tip="${esc(M[m].short + ': ' + o.title)}" aria-label="${esc(o.title)}">${tone(o.tone)}</button>`).join('')}</div></td>`; }).join('')}</tr>`).join('');
  const counts = m => { const c = { positive: 0, mixed: 0, negative: 0, neutral: 0 }; for (const t of D.review.topics) for (const o of t.models.find(x => x.model === m).observations) c[o.tone]++; return c; };
  const total = `<tr><th>All notes</th>${ORDER.map(m => { const c = counts(m); return `<td style="color:var(--text);font-variant-numeric:tabular-nums">${c.positive} good, ${c.mixed} mixed, ${c.negative} weak</td>`; }).join('')}</tr>`;
  $('#scoreboard').innerHTML = `<div class="table-scroll"><table class="scores"><thead><tr><th>Topic</th>${D.models.map(m => `<th><span data-m="${m.id}" style="display:inline-flex;gap:7px;align-items:center">${dot()}${esc(m.name)}</span></th>`).join('')}</tr></thead><tbody>${rows}${total}</tbody></table></div>`;
  const linked = n => {
    let cursor = 0, html = '';
    const links = (n.links || []).map(l => ({ ...l, index: n.text.indexOf(l.text) })).filter(l => l.index >= 0).sort((a, b) => a.index - b.index);
    for (const l of links) {
      if (l.index < cursor) continue;
      html += esc(n.text.slice(cursor, l.index));
      html += `<a data-note="${esc(l.noteId || n.id)}" role="button" tabindex="0">${esc(l.text)}</a>`;
      cursor = l.index + l.text.length;
    }
    return html + esc(n.text.slice(cursor));
  };
  $('#full-review').innerHTML = D.review.topics.map(t => {
    const aspects = t.aspects || [{ id: 'overall', title: 'Comments' }];
    return `<details class="fold" id="review-${esc(t.id)}"><summary>${esc(t.title)}</summary><div class="in"><div class="table-scroll"><table class="review"><thead><tr><th style="width:110px">Aspect</th>${t.models.map(m => `<th data-m="${m.model}"><span style="display:inline-flex;gap:7px;align-items:center">${dot()}${esc(M[m.model].name)}</span></th>`).join('')}</tr></thead><tbody>${aspects.map(a => `<tr><th>${esc(a.title)}</th>${t.models.map(m => { const list = m.observations.filter(o => o.aspect === a.id).map(o => NOTES.get(o.id)); return `<td data-m="${m.model}">${list.length ? list.map(n => `<p>${linked(n)}</p>`).join('') : '<span class="small">No comment</span>'}</td>`; }).join('')}</tr>`).join('')}</tbody></table></div></div></details>`;
  }).join('');
};

PAGES.costs = () => {
  const cmp = D.costs.comparison;
  const byRank = D.verdict.map(r => cmp.models.find(m => m.id === r.id));
  $('#score-cards').innerHTML = byRank.map((m, i) => {
    const c = m.scopes.combined, st = [['assets', '3D assets'], ['map', 'Map'], ['remainder', 'Rest of game']];
    return `<div class="score-card" data-m="${m.id}"><div class="name">${dot()}${esc(m.name)}<span class="badge" style="margin-left:auto">Verdict #${i + 1}</span></div><div class="big">≈ ${money0(c.usd)}</div><div class="row"><div><b>${esc(hours(c.active_seconds))}</b>active work</div><div><b>${esc(millions(c.tokens_total))}</b>tokens</div></div><div class="stack" aria-hidden="true">${st.map(([k], j) => `<i class="s${j}" style="flex:${m.scopes[k].usd.toFixed(3)}" data-tip="${esc(st[j][1] + ': ' + money(m.scopes[k].usd))}"></i>`).join('')}</div><div class="stack-key">${st.map(([k, l]) => `<span>${esc(l)}<b>${money0(m.scopes[k].usd)}</b></span>`).join('')}</div></div>`;
  }).join('');
  // scatter: time vs money
  const W = 640, H = 380, L = 58, R = 110, T = 16, B = 46, xMax = 48, yMax = 320;
  const X = v => L + v / xMax * (W - L - R), Y = v => H - B - v / yMax * (H - T - B);
  let g = '';
  for (let v = 0; v <= yMax; v += 80) g += `<line class="grid" x1="${L}" x2="${W - R}" y1="${Y(v)}" y2="${Y(v)}"/><text x="${L - 8}" y="${Y(v) + 4}" text-anchor="end">$${v}</text>`;
  for (let v = 0; v <= xMax; v += 12) g += `<line class="grid" x1="${X(v)}" x2="${X(v)}" y1="${T}" y2="${H - B}"/><text x="${X(v)}" y="${H - B + 18}" text-anchor="middle">${v} h</text>`;
  g += `<text x="${(L + W - R) / 2}" y="${H - 8}" text-anchor="middle">Active work time</text><text transform="translate(14 ${(T + H - B) / 2}) rotate(-90)" text-anchor="middle">Cost</text>`;
  const dots = cmp.models.map(m => { const c = m.scopes.combined, h = c.active_seconds / 3600, x = X(h), y = Y(c.usd); return `<g data-m="${m.id}"><circle cx="${x}" cy="${y}" r="8" style="fill:var(--mc)" data-tip="${esc(m.name + ': ' + hours(c.active_seconds) + ', ' + money(c.usd))}"/><text class="lab" x="${x + 13}" y="${y + 4}">${esc(M[m.id].short)}</text></g>`; }).join('');
  $('#scatter').innerHTML = `<svg class="scatter" viewBox="0 0 ${W} ${H}" role="img" aria-label="Cost against active work time for each model">${g}${dots}</svg>`;
  const rate = id => { const c = scope(id, 'combined'); return c.usd / (c.active_seconds / 3600); };
  $('#rate').innerHTML = bars(ORDER.map(id => ({ id, value: rate(id) })), v => '$' + v.toFixed(2) + '/h');
  const pick = (f, sign) => cmp.models.slice().sort((a, b) => sign * (a.scopes.combined[f] - b.scopes.combined[f]))[0];
  const glance = (label, m, value) => `<div class="tile top" data-m="${m.id}"><div class="v" style="font-size:22px">${esc(value)}</div><div class="l">${esc(label)}: ${esc(m.name)}</div></div>`;
  $('#glance').innerHTML = glance('Fastest', pick('active_seconds', 1), hours(pick('active_seconds', 1).scopes.combined.active_seconds)) + glance('Slowest', pick('active_seconds', -1), hours(pick('active_seconds', -1).scopes.combined.active_seconds)) + glance('Cheapest', pick('usd', 1), '≈ ' + money0(pick('usd', 1).scopes.combined.usd)) + glance('Most expensive', pick('usd', -1), '≈ ' + money0(pick('usd', -1).scopes.combined.usd));
  // stage panels
  const stages = [['combined', 'Whole project', ''], ['assets', 'Stage 1: 3D assets', '21 asset sets'], ['map', 'Stage 2: Map', 'One island from one reference'], ['remainder', 'Stage 3: Rest of the game', 'Everything after map creation']];
  $('#money').innerHTML = `<div class="row2">${stages.map(([k, t, h]) => stagePanel(t, h, k, 'usd', money)).join('')}</div>`;
  $('#time').innerHTML = `<div class="row2">${stages.map(([k, t, h]) => stagePanel(t, h, k, 'active_seconds', hm)).join('')}</div>`;
  // tokens
  const tok = ORDER.map(id => scope(id, 'combined'));
  $('#tokens').innerHTML = `<div class="row2">${stagePanel('Total tokens', 'Every category added up', 'combined', 'tokens_total', millions)}<div class="panel"><h4>Share read from cache</h4><p class="hint">Long sessions re-read their own context on every step</p>${bars(ORDER.map((id, i) => ({ id, value: tok[i].cache_read / tok[i].tokens_total * 100 })), v => v.toFixed(1) + '%', 100)}</div>${stagePanel('Output tokens', 'What the models wrote, thinking included', 'combined', 'output', millions)}<div class="panel"><h4>New input tokens</h4><p class="hint">Input that did not come from cache</p>${bars(ORDER.map((id, i) => ({ id, value: tok[i].input })), millions)}</div></div>`;
  // exact tables, same content as the original report
  const num = n => Number(n).toLocaleString('en-US', { maximumFractionDigits: 4 });
  const rateKeys = { claude: 'claude-opus-5-5', gemini: 'gemini-4-argon', muse: 'meta/muse-wonder' };
  const rateOf = (m, stage, f) => { const p = D.costs.prices_per_million; if (m.id === 'gpt') return (stage === 'remainder' ? D.costs.gpt_remainder_base_rates[f] : [p['gpt-6.1-sol'][f]]).map(money).join(' / ') + ' per 1M (base)'; return money(p[rateKeys[m.id]][f]) + ' per 1M'; };
  $('#exact').innerHTML = [['assets', 'Stage 1: 3D assets'], ['map', 'Stage 2: Map creation'], ['remainder', 'Stage 3: Remaining game'], ['game', 'Game (map + remaining game)'], ['combined', 'Combined (game + assets)']].map(([st, title]) => {
    const withRates = ['assets', 'map', 'remainder'].includes(st);
    const rows = cmp.models.map(m => {
      const v = m.scopes[st], cached = v.cache_read + v.cache_write_5m + v.cache_write_1h, writes = v.cache_write_5m + v.cache_write_1h > 0;
      const notes = [`Read${writes ? ': ' + num(v.cache_read) : ''}${withRates ? ' · ' + rateOf(m, st, 'cache_read') : ''}`];
      for (const [f, l] of [['cache_write_5m', 'Short cache write'], ['cache_write_1h', 'Long cache write']]) if (v[f] > 0) notes.push(`${l}: ${num(v[f])}${withRates ? ' · ' + rateOf(m, st, f) : ''}`);
      return `<tr><th>${esc(m.name)}</th><td><b>${num(v.input)}</b>${withRates ? `<small>${esc(rateOf(m, st, 'input'))}</small>` : ''}</td><td><b>${num(v.output)}</b>${withRates ? `<small>${esc(rateOf(m, st, 'output'))}</small>` : ''}</td><td><b>${num(cached)}</b><small>${notes.map(esc).join('<br>')}</small></td><td><b>${num(v.tokens_total)}</b></td><td><b>${esc(hm(v.active_seconds))}</b></td><td><b>${money(v.usd)}</b></td></tr>`;
    }).join('');
    return `<h4 style="margin:14px 0 6px">${esc(title)}</h4><div class="table-scroll"><table class="cost-table"><thead><tr><th>Model</th><th>Input tokens</th><th>Output tokens</th><th>Cached tokens</th><th>Total tokens</th><th>Active work time</th><th>Cost, USD</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }).join('');
  $('#notes').innerHTML = D.costNotes.map(n => `<li>${esc(n)}</li>`).join('');
  $('#legend').innerHTML = legend();
};

PAGES.brief = () => {
  const tabs = $$('.prompt-tabs [data-prompt-tab]');
  const show = id => {
    tabs.forEach(t => t.setAttribute('aria-selected', String(t.dataset.promptTab === id)));
    $$('.game-prompt').forEach(a => { a.hidden = a.id !== 'prompt-' + id; });
    try { history.replaceState(null, '', '#' + id); } catch {}
  };
  tabs.forEach(t => t.addEventListener('click', () => show(t.dataset.promptTab)));
  const start = location.hash.slice(1);
  show(['assets', 'map', 'game'].includes(start) ? start : 'assets');
  const copy = async (el, btn) => {
    const clone = el.cloneNode(true);
    $$('.copy,.prompt-reference', clone).forEach(x => x.remove());
    const text = clone.innerText.trim();
    let ok = false;
    try { await navigator.clipboard.writeText(text); ok = true; } catch {
      const ta = document.createElement('textarea'); ta.value = text; document.body.append(ta); ta.select();
      try { ok = document.execCommand('copy'); } catch {} ta.remove();
    }
    btn.textContent = ok ? 'Copied' : 'Select and copy by hand';
    setTimeout(() => { btn.textContent = 'Copy'; }, 1600);
  };
  $$('#prompt-assets>section, #prompt-game section').forEach(s => { if (s.closest('.spec-grid')) return; const b = document.createElement('button'); b.className = 'btn copy'; b.textContent = 'Copy'; b.onclick = () => copy(s, b); s.append(b); });
  const mp = $('#prompt-map');
  const b = document.createElement('button'); b.className = 'btn'; b.textContent = 'Copy the whole map prompt'; b.style.margin = '0 0 12px'; b.onclick = () => copy(mp, b); mp.prepend(b);
  $$('.prompt-reference img').forEach(i => i.setAttribute('data-zoom', ''));
};

document.addEventListener('DOMContentLoaded', () => {
  const page = document.body.dataset.page;
  PAGES[page]?.();
  if (location.hash && page !== 'brief') { const el = document.getElementById(decodeURIComponent(location.hash.slice(1))); if (el) { if (el.tagName === 'DETAILS') el.open = true; el.scrollIntoView(); } }
});
