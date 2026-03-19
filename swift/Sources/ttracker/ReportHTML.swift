// ReportHTML.swift — Embedded HTML/JS report template
// Layout: fixed left sidebar with section nav + scrollable main content area.
// Placeholders injected by ReportGenerator: __DAYS_DATA__ __ALL_DAYS__ __TODAY_TD__ __APP_COLORS__ __CAT_COLORS__ __WEEK_TOTALS__

let reportHTMLTemplate: String = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ttracker</title>
<style>
:root {
  --bg:#0f1117; --surface:#1a1d27; --surface2:#22263a; --border:#2e3352;
  --text:#e2e8f0; --muted:#8892a4; --accent:#4f86c6; --r:10px;
  --sidebar:180px;
  --font:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
}
* { box-sizing:border-box; margin:0; padding:0; }
html, body { height:100%; overflow:hidden; }
body {
  background:var(--bg); color:var(--text); font-family:var(--font);
  font-size:14px; line-height:1.6;
  display:flex;
}

/* ── Sidebar ── */
#sidebar {
  width:var(--sidebar); flex-shrink:0;
  background:var(--surface); border-right:1px solid var(--border);
  display:flex; flex-direction:column;
  overflow-y:auto; overflow-x:hidden;
}
.sidebar-logo {
  padding:16px 16px 12px;
  font-size:15px; font-weight:700; color:var(--text);
  border-bottom:1px solid var(--border);
  letter-spacing:-.01em;
}
.sidebar-logo span { color:var(--accent); }

.day-nav {
  padding:12px 10px;
  border-bottom:1px solid var(--border);
}
.day-nav-row {
  display:flex; gap:4px; margin-bottom:6px;
}
.day-nav-row button {
  flex:1; background:var(--surface2); border:1px solid var(--border);
  color:var(--text); border-radius:6px; padding:4px 6px;
  cursor:pointer; font-size:12px;
}
.day-nav-row button:hover { border-color:var(--accent); }
.day-nav-row button:disabled { opacity:0.35; cursor:default; }
.day-nav-row #btn-today { color:var(--accent); font-weight:600; }
#day-picker {
  width:100%; background:var(--surface2); border:1px solid var(--border);
  color:var(--text); border-radius:6px; padding:5px 8px;
  font-size:12px; cursor:pointer;
}

.nav-section-label {
  padding:12px 14px 4px;
  font-size:10px; font-weight:600; color:var(--muted);
  text-transform:uppercase; letter-spacing:.08em;
}
.nav-item {
  display:flex; align-items:center; gap:8px;
  padding:7px 14px; font-size:13px; color:var(--muted);
  text-decoration:none; cursor:pointer;
  border-left:2px solid transparent;
  transition:color .15s, background .15s;
}
.nav-item:hover { color:var(--text); background:var(--surface2); }
.nav-item.active { color:var(--text); border-left-color:var(--accent); background:rgba(79,134,198,.08); }
.nav-item .icon { font-size:14px; width:18px; text-align:center; flex-shrink:0; }

/* ── Main content ── */
#main {
  flex:1; overflow-y:auto; overflow-x:hidden;
  padding:28px 32px 60px;
  scroll-behavior:smooth;
}

/* ── Day header ── */
.day-header { margin-bottom:28px; }
.day-header h1 { font-size:22px; font-weight:700; margin-bottom:4px; }
.day-header p { color:var(--muted); font-size:13px; margin-bottom:12px; }
.stats { display:flex; flex-wrap:wrap; gap:10px; }
.stat {
  background:var(--surface); border:1px solid var(--border);
  border-radius:var(--r); padding:10px 18px; min-width:90px;
}
.stat.meeting { border-color:#e07b39; }
.stat .val { font-size:22px; font-weight:700; color:var(--accent); }
.stat.meeting .val { color:#e07b39; }
.stat .lbl { font-size:11px; color:var(--muted); margin-top:1px; }

/* ── Sections ── */
section {
  scroll-margin-top:16px;
  margin-bottom:48px;
}
.section-heading {
  font-size:16px; font-weight:700; color:var(--text);
  margin-bottom:18px; padding-bottom:10px;
  border-bottom:1px solid var(--border);
  display:flex; align-items:center; gap:8px;
}
.section-heading .icon { font-size:17px; }

/* ── Cards / grids ── */
h2 {
  font-size:12px; font-weight:600; margin-bottom:12px; color:var(--muted);
  text-transform:uppercase; letter-spacing:.07em;
}
.card {
  background:var(--surface); border:1px solid var(--border);
  border-radius:var(--r); padding:20px; margin-bottom:16px;
}
.card:last-child { margin-bottom:0; }
.grid2 { display:grid; grid-template-columns:1fr 1fr; gap:16px; margin-bottom:16px; }
.grid3 { display:grid; grid-template-columns:1fr 1fr 1fr; gap:16px; margin-bottom:16px; }

/* ── Bar charts ── */
.bar-row { display:flex; align-items:center; margin-bottom:7px; gap:10px; }
.bar-label {
  width:130px; font-size:12px; white-space:nowrap; overflow:hidden;
  text-overflow:ellipsis; flex-shrink:0;
}
.bar-track { flex:1; background:var(--surface2); border-radius:3px; height:14px; overflow:hidden; }
.bar-fill { height:100%; border-radius:3px; transition:width .4s; }
.bar-value { width:110px; font-size:11px; color:var(--muted); flex-shrink:0; text-align:right; }
.pct { opacity:.6; }

/* ── Tables ── */
table { table-layout:fixed; width:100%; border-collapse:collapse; }
th {
  text-align:left; color:var(--muted); font-weight:500; padding:7px 10px;
  border-bottom:1px solid var(--border); font-size:11px;
  text-transform:uppercase; letter-spacing:.06em;
  overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
}
td {
  padding:7px 10px; border-bottom:1px solid var(--border);
  vertical-align:middle; font-size:13px;
  overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
}
tr:last-child td { border-bottom:none; }
tr:hover td { background:var(--surface2); }
td.num { text-align:right; font-variant-numeric:tabular-nums; color:var(--muted); }
.col-app { width:22%; } .col-cat { width:13%; } .col-title { width:35%; }
.col-dur { width:12%; } .col-num { width:9%; text-align:right; }

/* ── Misc ── */
.dot {
  display:inline-block; width:8px; height:8px; border-radius:50%;
  margin-right:6px; vertical-align:middle; flex-shrink:0;
}
canvas { width:100%; display:block; border-radius:4px; }
.legend { display:flex; flex-wrap:wrap; gap:8px; margin-top:12px; }
.legend-item { display:flex; align-items:center; gap:5px; font-size:11px; color:var(--muted); }
.empty { color:var(--muted); font-style:italic; text-align:center; padding:20px 0; font-size:13px; }
.section-note { color:var(--muted); font-size:12px; margin-top:-6px; margin-bottom:12px; }
.table-note { color:var(--muted); font-size:11px; margin-top:6px; }
</style>
</head>
<body>

<!-- ── Sidebar ── -->
<nav id="sidebar">
  <div class="sidebar-logo">⏱ ttracker</div>

  <div class="day-nav">
    <div class="day-nav-row">
      <button id="btn-prev">&#8592;</button>
      <button id="btn-today">Today</button>
      <button id="btn-next">&#8594;</button>
    </div>
    <select id="day-picker"></select>
  </div>

  <div class="nav-section-label">Report</div>
  <a class="nav-item active" data-sec="sec-overview"  href="#">
    <span class="icon">📊</span> Overview
  </a>
  <a class="nav-item" data-sec="sec-timeline"  href="#">
    <span class="icon">📅</span> Timeline
  </a>
  <a class="nav-item" data-sec="sec-apps"      href="#">
    <span class="icon">🗂</span> Apps &amp; Time
  </a>
  <a class="nav-item" data-sec="sec-focus"     href="#">
    <span class="icon">🎯</span> Focus
  </a>
  <a class="nav-item" data-sec="sec-effort"    href="#">
    <span class="icon">⌨️</span> Effort
  </a>
  <a class="nav-item" data-sec="sec-sessions"  href="#">
    <span class="icon">📋</span> Sessions
  </a>
  <a class="nav-item" data-sec="sec-battery"   href="#" id="nav-battery" style="display:none">
    <span class="icon">🔋</span> Battery
  </a>
  <a class="nav-item" data-sec="sec-projects"  href="#" id="nav-projects" style="display:none">
    <span class="icon">📁</span> Projects
  </a>
</nav>

<!-- ── Main content ── -->
<div id="main">
  <div id="header"></div>
  <div id="content"></div>
</div>

<div id="timeline-tooltip" style="position:fixed;display:none;background:#1a1d27;border:1px solid #2e3352;border-radius:8px;padding:8px 12px;font-size:12px;pointer-events:none;z-index:200;color:#e2e8f0;max-width:260px;line-height:1.5;"></div>

<script>
'use strict';

var DAYS_DATA           = __DAYS_DATA__;
var ALL_DAYS            = __ALL_DAYS__;
var TODAY_TD            = __TODAY_TD__;
var APP_COLORS_MAP      = __APP_COLORS__;
var CATEGORY_COLORS_MAP = __CAT_COLORS__;
var WEEK_TOTALS         = __WEEK_TOTALS__;
var PX_TO_M             = 0.00025;

/* ── Helpers ── */

function esc(s) {
  if (!s) return '';
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function fmtDur(s) {
  s = Math.round(s);
  if (s < 60) return s + 's';
  var m = Math.floor(s / 60);
  if (m < 60) return m + 'm ' + (s % 60) + 's';
  return Math.floor(m / 60) + 'h ' + String(m % 60) + 'm';
}

function fmtDist(m) {
  if (m < 1) return (m * 100).toFixed(0) + ' cm';
  if (m < 1000) return m.toFixed(1) + ' m';
  return (m / 1000).toFixed(2) + ' km';
}

function fmtTime(ts) {
  var d = new Date(ts * 1000);
  var h = d.getHours(), mn = d.getMinutes();
  return (h < 10 ? '0' : '') + h + ':' + (mn < 10 ? '0' : '') + mn;
}

function fmtDateLong(td) {
  var d = new Date(td + 'T12:00:00');
  var days   = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
  var months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
  return days[d.getDay()] + ', ' + months[d.getMonth()] + ' ' + d.getDate() + ' ' + d.getFullYear();
}

function fmtDateShort(td) {
  var d = new Date(td + 'T12:00:00');
  var days   = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  var months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return days[d.getDay()] + ' ' + months[d.getMonth()] + ' ' + d.getDate() + ', ' + d.getFullYear();
}

/* ── Canvas helpers ── */

function setupCanvas(id, h) {
  var el = document.getElementById(id);
  if (!el) return null;
  var dpr = window.devicePixelRatio || 1;
  var W = el.parentElement.clientWidth - 44;
  el.width  = W * dpr; el.height = h * dpr;
  el.style.width = W + 'px'; el.style.height = h + 'px';
  var ctx = el.getContext('2d'); ctx.scale(dpr, dpr);
  return { ctx: ctx, W: W, H: h };
}

function hGridLines(ctx, chartW, H, padL, padT, chartH, maxVal, n, fmtFn) {
  for (var i = 0; i <= n; i++) {
    var v = maxVal * i / n;
    var y = padT + chartH - (i / n) * chartH;
    ctx.fillStyle = '#8892a4';
    ctx.font = '10px -apple-system,sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText(fmtFn ? fmtFn(v) : String(Math.round(v)), padL - 5, y + 4);
    ctx.strokeStyle = '#2e3352'; ctx.lineWidth = 0.5;
    ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(padL + chartW, y); ctx.stroke();
  }
}

/* ── Bar chart rendering ── */

function renderBars(containerId, rows, keyName, keySeconds, colorMap, total) {
  var el = document.getElementById(containerId);
  if (!el) return;
  if (!rows || !rows.length) { el.innerHTML = '<p class="empty">No data.</p>'; return; }
  var html = '';
  rows.forEach(function(r) {
    var name = r[keyName], secs = r[keySeconds] || 0;
    var pct = total > 0 ? (secs / total * 100) : 0;
    var color = colorMap[name] || '#888';
    html += '<div class="bar-row">' +
      '<div class="bar-label" title="' + esc(name) + '">' + esc(name) + '</div>' +
      '<div class="bar-track"><div class="bar-fill" style="width:' + pct.toFixed(1) + '%;background:' + color + '"></div></div>' +
      '<div class="bar-value">' + fmtDur(secs) + ' <span class="pct">(' + Math.round(pct) + '%)</span></div>' +
      '</div>';
  });
  el.innerHTML = html;
}

/* ── Header ── */

function renderHeader(td, D) {
  var total    = (D.todayByApp || []).reduce(function(s, r) { return s + r.total_seconds; }, 0);
  var it       = D.inputTotals || { keystrokes: 0, clicks: 0, distance_m: 0, scrolls: 0 };
  var mtg      = D.meetings    || { total_seconds: 0, session_count: 0 };
  var appCount = (D.todayByApp || []).length;

  var statHtml =
    '<div class="stat"><div class="val">' + fmtDur(total) + '</div><div class="lbl">Total active</div></div>' +
    '<div class="stat"><div class="val">' + appCount + '</div><div class="lbl">Apps used</div></div>';
  if (mtg.total_seconds > 0) {
    statHtml += '<div class="stat meeting"><div class="val">' + fmtDur(mtg.total_seconds) +
      '</div><div class="lbl">In meetings</div></div>';
  }
  if (it.keystrokes > 0 || it.clicks > 0 || it.scrolls > 0) {
    statHtml +=
      '<div class="stat"><div class="val">' + it.keystrokes.toLocaleString() + '</div><div class="lbl">Keystrokes</div></div>' +
      '<div class="stat"><div class="val">' + it.clicks.toLocaleString()     + '</div><div class="lbl">Clicks</div></div>' +
      '<div class="stat"><div class="val">' + fmtDist(it.distance_m)         + '</div><div class="lbl">Mouse distance</div></div>' +
      '<div class="stat"><div class="val">' + it.scrolls.toLocaleString()    + '</div><div class="lbl">Scrolls</div></div>';
  }

  var activeFromTo = '';
  if (D.firstTs && D.lastTs) {
    activeFromTo = ' &mdash; <span style="color:var(--muted);font-size:13px">Active ' +
      fmtTime(D.firstTs) + '&ndash;' + fmtTime(D.lastTs) + '</span>';
  }

  var isToday   = (td === TODAY_TD);
  var dateLabel = fmtDateLong(td) + (isToday
    ? ' <span style="color:var(--accent);font-size:13px">(today)</span>' : '');

  document.getElementById('header').innerHTML =
    '<div class="day-header">' +
    '<h1>&#9201; ' + dateLabel + activeFromTo + '</h1>' +
    '<div class="stats">' + statHtml + '</div>' +
    '</div>';
}

/* ── Table renderers ── */

function renderActivitiesTable(D) {
  var tbody = document.getElementById('tbody-activities');
  if (!tbody) return;
  var html = '';
  (D.allTitles || []).forEach(function(r) {
    var catColor = CATEGORY_COLORS_MAP[r.category] || '#888';
    var appColor = APP_COLORS_MAP[r.app_name] || '#888';
    var title    = r.window_title || '\u2014';
    var ksStr    = r.keystrokes   ? r.keystrokes.toLocaleString()   : '\u2014';
    var clStr    = r.mouse_clicks ? r.mouse_clicks.toLocaleString() : '\u2014';
    html += '<tr>' +
      '<td class="col-app"><span class="dot" style="background:' + appColor + '"></span>' + esc(r.app_name) + '</td>' +
      '<td class="col-cat"><span class="dot" style="background:' + catColor + '"></span>' + esc(r.category) + '</td>' +
      '<td class="col-title" title="' + esc(title) + '">' + esc(title) + '</td>' +
      '<td class="col-dur">' + fmtDur(r.total_seconds) + '</td>' +
      '<td class="col-num">' + ksStr + '</td>' +
      '<td class="col-num">' + clStr + '</td>' +
      '</tr>';
  });
  tbody.innerHTML = html;
}

function renderFocusTable(D) {
  var tbody = document.getElementById('tbody-focus');
  if (!tbody) return;
  var html = '';
  (D.focusSessions || []).forEach(function(r, i) {
    var color = APP_COLORS_MAP[r.app_name] || '#888';
    html += '<tr>' +
      '<td style="width:5%;color:var(--muted)">#' + (i + 1) + '</td>' +
      '<td style="width:20%"><span class="dot" style="background:' + color + '"></span>' + esc(r.app_name) + '</td>' +
      '<td style="width:38%" title="' + esc(r.window_title) + '">' + esc(r.window_title || '\u2014') + '</td>' +
      '<td style="width:13%">' + fmtDur(r.duration_seconds) + '</td>' +
      '<td style="width:12%">' + fmtTime(r.started_at) + '</td>' +
      '<td style="width:12%;text-align:right;color:var(--muted)">' + (r.keystrokes ? r.keystrokes.toLocaleString() : '\u2014') + '</td>' +
      '</tr>';
  });
  tbody.innerHTML = html;
}

function renderSwitchFreqTable(D) {
  var tbody = document.getElementById('tbody-switchfreq');
  if (!tbody) return;
  var html = '';
  (D.switchFreq || []).forEach(function(r) {
    var color  = APP_COLORS_MAP[r.app_name] || '#888';
    var avgStr = r.avg_time_before_switch ? fmtDur(r.avg_time_before_switch) : '\u2014';
    html += '<tr>' +
      '<td><span class="dot" style="background:' + color + '"></span>' + esc(r.app_name) + '</td>' +
      '<td style="text-align:right;color:var(--muted)">' + r.switch_count + '</td>' +
      '<td>' + avgStr + '</td>' +
      '</tr>';
  });
  tbody.innerHTML = html;
}

/* ── Canvas charts ── */

function drawWeekChart(td, D) {
  var tdIdx    = ALL_DAYS.indexOf(td);
  var startIdx = Math.max(0, tdIdx - 6);
  var week7    = ALL_DAYS.slice(startIdx, tdIdx + 1);
  while (week7.length < 7) { week7.unshift(null); }

  var g = setupCanvas('c-week', 200);
  if (!g) return;
  var ctx = g.ctx, W = g.W, H = g.H;
  var PL = 50, PR = 10, PT = 10, PB = 40;
  var cW = W - PL - PR, cH = H - PT - PB;

  var maxV = 1;
  week7.forEach(function(d) {
    if (d) maxV = Math.max(maxV, WEEK_TOTALS[d] || 0);
  });

  hGridLines(ctx, cW, H, PL, PT, cH, maxV, 4, fmtDur);

  var bW = cW / 7;
  week7.forEach(function(d, i) {
    var secs = d ? (WEEK_TOTALS[d] || 0) : 0;
    var bh   = secs > 0 ? (secs / maxV) * cH : 0;
    var bx   = PL + i * bW + bW * 0.12;
    var by   = PT + cH - bh;
    var bww  = bW * 0.76;

    var fillColor = '#2e3352';
    if (d && secs > 0) {
      if      (d === td)       fillColor = '#4f86c6';
      else if (d === TODAY_TD) fillColor = '#6fa0d8';
      else                     fillColor = '#3a5a8c';
    }
    ctx.fillStyle = fillColor;
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(bx, by, bww, Math.max(bh, 1), [4, 4, 0, 0]);
    else ctx.rect(bx, by, bww, Math.max(bh, 1));
    ctx.fill();

    if (d === td && td !== TODAY_TD && secs > 0) {
      ctx.strokeStyle = 'rgba(255,255,255,0.6)';
      ctx.lineWidth   = 1.5;
      ctx.strokeRect(bx, by, bww, bh);
    }

    if (d && secs > 0) {
      ctx.fillStyle = '#e2e8f0'; ctx.font = '9px -apple-system,sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(fmtDur(secs), bx + bww / 2, by - 3);
    }
    if (d) {
      ctx.fillStyle = '#8892a4'; ctx.font = '10px -apple-system,sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(d.slice(5), bx + bww / 2, PT + cH + 15);
      var dayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
      var dt2 = new Date(d + 'T12:00:00');
      ctx.fillStyle = (d === td) ? '#4f86c6' : '#8892a4';
      ctx.font = '9px -apple-system,sans-serif';
      ctx.fillText(dayNames[dt2.getDay()], bx + bww / 2, PT + cH + 28);
    } else {
      ctx.fillStyle = '#4e5568'; ctx.font = '10px -apple-system,sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('\u2014', bx + bww / 2, PT + cH + 15);
    }
  });
}

/* Merge adjacent same-app timeline entries (gap < 90s) to reduce draw calls */
function mergeTimeline(timeline) {
  if (!timeline || !timeline.length) return [];
  var sorted = timeline.slice().sort(function(a, b) { return a.started_at - b.started_at; });
  var merged = [];
  var cur = Object.assign({}, sorted[0]);
  for (var i = 1; i < sorted.length; i++) {
    var e = sorted[i];
    if (e.app_name === cur.app_name && !e.is_idle && !cur.is_idle &&
        e.started_at - cur.ended_at < 90) {
      cur.ended_at = Math.max(cur.ended_at, e.ended_at);
      cur.duration_seconds = cur.ended_at - cur.started_at;
    } else {
      merged.push(cur);
      cur = Object.assign({}, e);
    }
  }
  merged.push(cur);
  return merged;
}

function drawTimelineChart(td, D) {
  var timeline = mergeTimeline(D.timeline || []);

  var _sd = new Date(D.dayStartTs * 1000);
  var alignedStart = D.dayStartTs - (_sd.getMinutes() * 60 + _sd.getSeconds());

  var tsArr = [];
  timeline.forEach(function(e) {
    if (!e.is_idle) {
      tsArr.push((e.started_at - alignedStart) / 3600);
      tsArr.push((e.ended_at   - alignedStart) / 3600);
    }
  });

  var firstHour = tsArr.length ? Math.max(0,  Math.floor(Math.min.apply(null, tsArr)) - 1) : 0;
  var lastHour  = tsArr.length ? Math.min(23, Math.ceil( Math.max.apply(null, tsArr)) + 1) : 23;
  var ROWS      = lastHour - firstHour + 1;
  var ROW       = Math.max(16, Math.floor(220 / ROWS));
  var LW        = 44;
  var padding   = 10;
  var chartH    = ROWS * ROW;
  var totalH    = chartH + padding + 20;

  var el = document.getElementById('c-timeline');
  if (!el) return;
  var dpr = window.devicePixelRatio || 1;
  var W   = el.parentElement.clientWidth - 44;
  el.width  = W * dpr; el.height = totalH * dpr;
  el.style.width = W + 'px'; el.style.height = totalH + 'px';
  var ctx = el.getContext('2d'); ctx.scale(dpr, dpr);
  var cW  = W - LW - 6;

  for (var hBg = 0; hBg < ROWS; hBg++) {
    ctx.fillStyle = hBg % 2 === 0 ? '#1a1d27' : '#1d2130';
    ctx.fillRect(LW, hBg * ROW, cW, ROW);
  }

  ctx.fillStyle = '#8892a4'; ctx.font = '9px -apple-system,sans-serif'; ctx.textAlign = 'right';
  var labelEvery = ROWS <= 12 ? 1 : 2;
  var startClockH = new Date(D.dayStartTs * 1000).getHours();
  for (var hL = firstHour; hL <= lastHour; hL++) {
    if ((hL - firstHour) % labelEvery === 0) {
      var rowY = (hL - firstHour) * ROW + ROW / 2 + 3;
      var clockH = (startClockH + hL) % 24;
      ctx.fillText((clockH < 10 ? '0' : '') + clockH + ':00', LW - 4, rowY);
    }
  }

  var rects = [];
  timeline.forEach(function(e) {
    var eS0    = (e.started_at - alignedStart) / 3600;
    var eS1    = (e.ended_at   - alignedStart) / 3600;
    var rStart = Math.max(0,    Math.floor(eS0 - firstHour));
    var rEnd   = Math.min(ROWS, Math.ceil( eS1 - firstHour));
    for (var rowIdx = rStart; rowIdx < rEnd; rowIdx++) {
      var rowHourS = firstHour + rowIdx;
      var rowHourE = rowHourS + 1;
      var colS = Math.max(eS0, rowHourS);
      var colE = Math.min(eS1, rowHourE);
      if (colE <= colS) continue;
      var rx  = LW + (colS - rowHourS) * cW;
      var rw  = (colE - colS) * cW;
      var ry  = rowIdx * ROW + 1;
      var rh2 = ROW - 2;
      ctx.fillStyle   = APP_COLORS_MAP[e.app_name] || '#888';
      ctx.globalAlpha = e.is_idle ? 0.25 : 0.85;
      ctx.fillRect(rx, ry, Math.max(rw, 1), rh2);
      ctx.globalAlpha = 1;
      rects.push({ x: rx, y: ry, w: Math.max(rw, 1), h: rh2, e: e });
    }
  });

  ctx.strokeStyle = '#2e3352'; ctx.lineWidth = 0.5;
  for (var gl = 0; gl <= ROWS; gl++) {
    ctx.beginPath(); ctx.moveTo(LW, gl * ROW); ctx.lineTo(LW + cW, gl * ROW); ctx.stroke();
  }

  if (td === TODAY_TD) {
    var nowH = (Date.now() / 1000 - alignedStart) / 3600;
    if (nowH >= firstHour && nowH <= lastHour + 1) {
      var ny = (nowH - firstHour) * ROW;
      ctx.strokeStyle = 'rgba(255,68,68,0.85)'; ctx.lineWidth = 1.5;
      ctx.setLineDash([4, 3]);
      ctx.beginPath(); ctx.moveTo(LW, ny); ctx.lineTo(LW + cW, ny); ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  var leg = document.getElementById('legend-timeline');
  if (leg) {
    leg.innerHTML = '';
    var seenApps = {};
    timeline.forEach(function(e) { seenApps[e.app_name] = true; });
    Object.keys(seenApps).sort().forEach(function(app) {
      var item = document.createElement('div'); item.className = 'legend-item';
      var dot  = document.createElement('span'); dot.className = 'dot';
      dot.style.background = APP_COLORS_MAP[app] || '#888';
      item.appendChild(dot); item.appendChild(document.createTextNode(app));
      leg.appendChild(item);
    });
  }

  var tooltip = document.getElementById('timeline-tooltip');
  el.onmousemove = function(ev) {
    var rect2 = el.getBoundingClientRect();
    var mx = (ev.clientX - rect2.left) * (W / rect2.width);
    var my = (ev.clientY - rect2.top)  * (totalH / rect2.height);
    var hit = null;
    for (var ri = rects.length - 1; ri >= 0; ri--) {
      var r2 = rects[ri];
      if (mx >= r2.x && mx <= r2.x + r2.w && my >= r2.y && my <= r2.y + r2.h) {
        hit = r2.e; break;
      }
    }
    if (hit) {
      tooltip.style.display = 'block';
      tooltip.style.left = (ev.clientX + 12) + 'px';
      tooltip.style.top  = (ev.clientY - 10) + 'px';
      tooltip.innerHTML  = '<strong>' + esc(hit.app_name) + '</strong><br>' +
        fmtTime(hit.started_at) + ' &ndash; ' + fmtTime(hit.ended_at) + ' &middot; ' + fmtDur(hit.duration_seconds) +
        (hit.window_title
          ? '<br><span style="color:#8892a4">' + esc(String(hit.window_title).slice(0, 60)) + '</span>'
          : '');
    } else {
      tooltip.style.display = 'none';
    }
  };
  el.onmouseleave = function() { tooltip.style.display = 'none'; };
}

function drawInputChart(D) {
  var g = setupCanvas('c-input', 160);
  if (!g) return;
  var ctx = g.ctx, W = g.W, H = g.H;
  var PL = 55, PR = 10, PT = 10, PB = 30;
  var cW = W - PL - PR, cH = H - PT - PB;
  var inputByHour = D.inputByHour || [];
  if (!inputByHour.length) {
    ctx.fillStyle = '#8892a4'; ctx.font = '13px -apple-system,sans-serif';
    ctx.textAlign = 'center'; ctx.fillText('No input data yet', W / 2, H / 2); return;
  }
  var maxK = inputByHour.reduce(function(a, b) {
    return Math.max(a, (b.keystrokes || 0) + (b.clicks || 0));
  }, 1);
  hGridLines(ctx, cW, H, PL, PT, cH, maxK, 4, null);

  ctx.save();
  ctx.translate(12, PT + cH / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.fillStyle = '#8892a4'; ctx.font = '10px -apple-system,sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText('keys / clicks', 0, 0);
  ctx.restore();

  var bW = cW / 24;
  for (var h = 0; h < 24; h++) {
    var rowH = inputByHour.find(function(r) { return r.hour_idx === h; });
    var ks   = (rowH ? rowH.keystrokes : 0) || 0;
    var cl   = (rowH ? rowH.clicks     : 0) || 0;
    var bx   = PL + h * bW + 1, bww = bW - 2;
    if (ks + cl > 0) {
      var khH = (ks / maxK) * cH, clH = (cl / maxK) * cH;
      ctx.fillStyle = '#4f86c6';
      ctx.fillRect(bx, PT + cH - khH - clH, bww, khH);
      ctx.fillStyle = '#e07b39';
      ctx.fillRect(bx, PT + cH - clH, bww, clH);
    }
    if (h % 3 === 0) {
      ctx.fillStyle = '#8892a4'; ctx.font = '9px -apple-system,sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText((h < 10 ? '0' : '') + h, bx + bww / 2, PT + cH + 14);
    }
  }
}

function drawSwitchesChart(D) {
  var g = setupCanvas('c-switches', 160);
  if (!g) return;
  var ctx = g.ctx, W = g.W, H = g.H;
  var PL = 40, PR = 10, PT = 10, PB = 30;
  var cW = W - PL - PR, cH = H - PT - PB;
  var switchByHour = D.switchByHour || [];
  if (!switchByHour.length) {
    ctx.fillStyle = '#8892a4'; ctx.font = '13px -apple-system,sans-serif';
    ctx.textAlign = 'center'; ctx.fillText('No switch data yet', W / 2, H / 2); return;
  }
  var maxV = switchByHour.reduce(function(a, b) { return Math.max(a, b.switch_count); }, 1);
  hGridLines(ctx, cW, H, PL, PT, cH, maxV, 4, null);
  var bW = cW / 24;
  for (var h = 0; h < 24; h++) {
    var rowS = switchByHour.find(function(r) { return r.hour_idx === h; });
    var v    = (rowS ? rowS.switch_count : 0) || 0;
    var bx   = PL + h * bW + 1, bww = bW - 2;
    if (v > 0) {
      var bh3 = (v / maxV) * cH;
      ctx.fillStyle = '#8b6fbe';
      ctx.fillRect(bx, PT + cH - bh3, bww, bh3);
    }
    if (h % 3 === 0) {
      ctx.fillStyle = '#8892a4'; ctx.font = '9px -apple-system,sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText((h < 10 ? '0' : '') + h, bx + bww / 2, PT + cH + 14);
    }
  }
}

function drawBatteryChart(D) {
  var g = setupCanvas('c-battery', 120);
  if (!g) return;
  var ctx = g.ctx, W = g.W, H = g.H;
  var bh = D.batteryHist;
  if (!bh || !bh.length) return;
  var PL = 40, PR = 10, PT = 10, PB = 24;
  var cW = W - PL - PR, cH = H - PT - PB;
  var tMin = bh[0].timestamp, tMax = bh[bh.length - 1].timestamp;
  var tRange = Math.max(tMax - tMin, 1);
  hGridLines(ctx, cW, H, PL, PT, cH, 100, 4, function(v) { return v + '%'; });
  ctx.beginPath();
  bh.forEach(function(pt, i) {
    var x = PL + ((pt.timestamp - tMin) / tRange) * cW;
    var y = PT + cH - (pt.battery_percent / 100) * cH;
    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  });
  ctx.strokeStyle = '#5bb56b'; ctx.lineWidth = 2; ctx.stroke();
  for (var i = 1; i < bh.length; i++) {
    var p = bh[i - 1], c = bh[i];
    if (p.is_charging) {
      var x0 = PL + ((p.timestamp - tMin) / tRange) * cW;
      var x1 = PL + ((c.timestamp - tMin) / tRange) * cW;
      var y0 = PT + cH - (p.battery_percent / 100) * cH;
      var y1 = PT + cH - (c.battery_percent / 100) * cH;
      ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1);
      ctx.strokeStyle = '#e07b39'; ctx.lineWidth = 2; ctx.stroke();
    }
  }
}

/* ── Content renderer ── */

function renderContent(td, D) {
  var total     = (D.todayByApp  || []).reduce(function(s, r) { return s + r.total_seconds; }, 0);
  var totalCat  = (D.byCategory  || []).reduce(function(s, r) { return s + r.total_seconds; }, 0);
  var totalDom  = (D.domains     || []).reduce(function(s, r) { return s + r.total_seconds; }, 0);
  var totalProj = (D.projects    || []).reduce(function(s, r) { return s + r.total_seconds; }, 0);
  var totalMtg  = (D.meetings    || { total_seconds: 0 }).total_seconds;
  var mtgCount  = (D.meetings    || { session_count: 0 }).session_count;
  var hasBattery  = D.batteryHist  && D.batteryHist.length > 0;
  var hasProjects = D.projects     && D.projects.length > 0;

  var html = '';

  /* ── Section 1: Overview — puts today in the context of the week ── */
  html += '<section id="sec-overview">';
  html += '<div class="section-heading"><span class="icon">📊</span> Overview</div>';
  html += '<div class="card"><h2>Last 7 tracking days</h2><canvas id="c-week" height="200"></canvas></div>';
  html += '</section>';

  /* ── Section 2: Timeline — when did you work? ── */
  html += '<section id="sec-timeline">';
  html += '<div class="section-heading"><span class="icon">📅</span> Your Day</div>';
  html += '<div class="card">' +
    '<canvas id="c-timeline"></canvas>' +
    '<div class="legend" id="legend-timeline"></div></div>';
  html += '</section>';

  /* ── Section 3: Apps & Time — where did time go? ── */
  html += '<section id="sec-apps">';
  html += '<div class="section-heading"><span class="icon">🗂</span> Where Time Went</div>';
  html += '<div class="grid2">';
  html += '<div class="card"><h2>By app</h2><div id="bars-app"></div></div>';
  html += '<div class="card"><h2>By category</h2><div id="bars-cat"></div></div>';
  html += '</div>';

  // Meetings row (only if meetings exist)
  var mtgCardHtml = '<div class="card"><h2>Meetings &amp; calls</h2>';
  if (D.meetingByApp && D.meetingByApp.length) {
    mtgCardHtml += '<p class="section-note">' + fmtDur(totalMtg) + ' across ' + mtgCount +
      ' session' + (mtgCount !== 1 ? 's' : '') + '</p>';
    mtgCardHtml += '<div id="bars-meetings"></div>';
  } else {
    mtgCardHtml += '<p class="empty">No meetings recorded.</p>';
  }
  mtgCardHtml += '</div>';

  html += '<div class="grid2">';
  html += mtgCardHtml;
  html += '<div class="card"><h2>Browser domains</h2><div id="bars-domains"></div></div>';
  html += '</div>';
  html += '</section>';

  /* ── Section 4: Focus & Attention — quality of work ── */
  html += '<section id="sec-focus">';
  html += '<div class="section-heading"><span class="icon">🎯</span> Focus &amp; Attention</div>';

  html += '<div class="card"><h2>Longest uninterrupted sessions</h2>';
  if (D.focusSessions && D.focusSessions.length) {
    html += '<table><thead><tr>' +
      '<th style="width:5%">#</th><th style="width:20%">App</th>' +
      '<th style="width:38%">Title</th><th style="width:13%">Duration</th>' +
      '<th style="width:12%">Start</th><th style="width:12%;text-align:right">Keys</th>' +
      '</tr></thead><tbody id="tbody-focus"></tbody></table>';
  } else {
    html += '<p class="empty">No data yet.</p>';
  }
  html += '</div>';

  html += '<div class="grid2">';
  html += '<div class="card"><h2>App switches per hour</h2>' +
    '<p class="section-note">How often you changed windows</p>' +
    '<canvas id="c-switches" height="160"></canvas></div>';
  html += '<div class="card"><h2>Switch frequency</h2>';
  if (D.switchFreq && D.switchFreq.length) {
    html += '<table><thead><tr>' +
      '<th>App</th>' +
      '<th style="text-align:right">Switches</th>' +
      '<th>Avg time before</th>' +
      '</tr></thead><tbody id="tbody-switchfreq"></tbody></table>';
  } else {
    html += '<p class="empty">No switches recorded yet.</p>';
  }
  html += '</div>';
  html += '</div>';
  html += '</section>';

  /* ── Section 5: Effort & Input — how hard did you work? ── */
  html += '<section id="sec-effort">';
  html += '<div class="section-heading"><span class="icon">⌨️</span> Effort &amp; Input</div>';
  html += '<div class="card"><h2>Input intensity — keystrokes (blue) + clicks (orange) per hour</h2>' +
    '<canvas id="c-input" height="160"></canvas></div>';
  html += '</section>';

  /* ── Section 6: All Sessions ── */
  html += '<section id="sec-sessions">';
  html += '<div class="section-heading"><span class="icon">📋</span> All Sessions</div>';
  html += '<div class="card">';
  if (D.allTitles && D.allTitles.length) {
    html += '<table><thead><tr>' +
      '<th class="col-app">App</th><th class="col-cat">Category</th>' +
      '<th class="col-title">Window / Tab</th><th class="col-dur">Duration</th>' +
      '<th class="col-num">Keys</th><th class="col-num">Clicks</th>' +
      '</tr></thead><tbody id="tbody-activities"></tbody></table>';
    if (D.allTitles.length >= 50) {
      html += '<p class="table-note">Showing top 50 sessions</p>';
    }
  } else {
    html += '<p class="empty">No data yet.</p>';
  }
  html += '</div>';
  html += '</section>';

  /* ── Section 7: Battery (conditional) ── */
  if (hasBattery) {
    html += '<section id="sec-battery">';
    html += '<div class="section-heading"><span class="icon">🔋</span> Battery</div>';
    html += '<div class="card"><canvas id="c-battery" height="120"></canvas></div>';
    html += '</section>';
  }

  /* ── Section 8: Projects (conditional) ── */
  if (hasProjects) {
    html += '<section id="sec-projects">';
    html += '<div class="section-heading"><span class="icon">📁</span> Projects &amp; Directories</div>';
    html += '<div class="card"><div id="bars-projects"></div></div>';
    html += '</section>';
  }

  document.getElementById('content').innerHTML = html;

  /* ── Populate bar charts and tables (fast, text-based) ── */
  renderBars('bars-app',      D.todayByApp   || [], 'app_name', 'total_seconds', APP_COLORS_MAP, total);
  renderBars('bars-cat',      D.byCategory   || [], 'category', 'total_seconds', CATEGORY_COLORS_MAP, totalCat);
  renderBars('bars-meetings', D.meetingByApp || [], 'app_name', 'total_seconds', APP_COLORS_MAP, totalMtg);
  renderBars('bars-domains',  D.domains      || [], 'domain',   'total_seconds', APP_COLORS_MAP, totalDom);
  if (hasProjects) renderBars('bars-projects', D.projects, 'project', 'total_seconds', APP_COLORS_MAP, totalProj);

  renderActivitiesTable(D);
  renderFocusTable(D);
  renderSwitchFreqTable(D);

  /* ── Show/hide conditional sidebar nav items ── */
  var navBat  = document.getElementById('nav-battery');
  var navProj = document.getElementById('nav-projects');
  if (navBat)  navBat.style.display  = hasBattery  ? 'flex' : 'none';
  if (navProj) navProj.style.display = hasProjects ? 'flex' : 'none';

  /* ── Re-register IntersectionObserver for active nav tracking ── */
  _navItemsCache = null;  // invalidate cache after DOM rebuild
  setupSectionObserver();

  /* ── Defer heavy canvas draws to next animation frame ── */
  requestAnimationFrame(function() {
    drawWeekChart(td, D);
    drawTimelineChart(td, D);
    drawInputChart(D);
    drawSwitchesChart(D);
    if (hasBattery) drawBatteryChart(D);
  });
}

/* ── renderDay ── */

function renderDay(td) {
  var D = DAYS_DATA[td] || {
    todayByApp: [], byCategory: [], domains: [],
    meetings: { total_seconds: 0, session_count: 0 },
    meetingByApp: [], timeline: [], inputByHour: [], switchByHour: [],
    focusSessions: [], allTitles: [],
    inputTotals: { keystrokes: 0, clicks: 0, distance_m: 0, scrolls: 0 },
    batteryHist: [], switchFreq: [], projects: [],
    dayStartTs: 0, firstTs: null, lastTs: null
  };
  renderHeader(td, D);
  renderContent(td, D);
}

/* ── Section observer — highlights active nav item on scroll ── */

var _sectionObserver = null;
var _navItemsCache = null;

function setupSectionObserver() {
  if (_sectionObserver) _sectionObserver.disconnect();
  _navItemsCache = Array.from(document.querySelectorAll('.nav-item'));
  var mainEl = document.getElementById('main');
  _sectionObserver = new IntersectionObserver(function(entries) {
    entries.forEach(function(entry) {
      if (entry.isIntersecting) {
        var secId = entry.target.id;
        (_navItemsCache || []).forEach(function(a) {
          a.classList.toggle('active', a.dataset.sec === secId);
        });
      }
    });
  }, { root: mainEl, threshold: 0.25 });

  document.querySelectorAll('section[id^="sec-"]').forEach(function(el) {
    _sectionObserver.observe(el);
  });
}

/* ── Sidebar nav clicks — smooth scroll inside #main ── */

document.querySelectorAll('.nav-item').forEach(function(a) {
  a.addEventListener('click', function(e) {
    e.preventDefault();
    var secId = a.dataset.sec;
    var sec   = document.getElementById(secId);
    if (sec) sec.scrollIntoView({ behavior: 'smooth', block: 'start' });
    document.querySelectorAll('.nav-item').forEach(function(b) { b.classList.remove('active'); });
    a.classList.add('active');
  });
});

/* ── Day navigation ── */

var currentDay = TODAY_TD;

function navigate(td) {
  currentDay = td;
  document.getElementById('day-picker').value = td;
  document.getElementById('btn-prev').disabled = (ALL_DAYS.indexOf(td) === 0);
  document.getElementById('btn-next').disabled = (ALL_DAYS.indexOf(td) === ALL_DAYS.length - 1);
  renderDay(td);
  document.getElementById('main').scrollTop = 0;
  // Reset active nav to Overview
  document.querySelectorAll('.nav-item').forEach(function(a) {
    a.classList.toggle('active', a.dataset.sec === 'sec-overview');
  });
}

var picker = document.getElementById('day-picker');
var allDaysRev = ALL_DAYS.slice().reverse();
allDaysRev.forEach(function(d) {
  var opt = document.createElement('option');
  opt.value = d;
  var label = fmtDateShort(d);
  if (d === TODAY_TD) label += ' (today)';
  opt.textContent = label;
  picker.appendChild(opt);
});

document.getElementById('btn-prev').addEventListener('click', function() {
  var i = ALL_DAYS.indexOf(currentDay);
  if (i > 0) navigate(ALL_DAYS[i - 1]);
});
document.getElementById('btn-next').addEventListener('click', function() {
  var i = ALL_DAYS.indexOf(currentDay);
  if (i < ALL_DAYS.length - 1) navigate(ALL_DAYS[i + 1]);
});
document.getElementById('btn-today').addEventListener('click', function() { navigate(TODAY_TD); });
document.getElementById('day-picker').addEventListener('change', function() { navigate(this.value); });

navigate(TODAY_TD);
</script>
</body>
</html>
"""#
