/* Arch View viewer — pure rendering layer.
 * Layout (Tarjan SCC / feedback edges / layering / coordinates / cycle paths)
 * is computed on the Lua side; this file does zero layout work: it directly
 * consumes the rect/layer of every view node, the cycle_break boolean of
 * every view edge, the cycle/has_cycle_subtree booleans of every node, and
 * the per-view cycle_lines list in window.ARCH_VIEW_DATA.views.
 * The visual grammar (colors / geometry constants) is copied from
 * unclebob/arch-view; see monopoly research/unclebob-arch-view-visual-grammar.md.
 * Interactions (monopoly #229): clicking a leaf node opens its source_text in
 * an in-page modal, +/- zoom the scene via CSS transform, and a viewport
 * WIDTH change rebuilds the scene re-centered on the wider canvas (a uniform
 * x shift, since the Lua side centers every layer group on its canvas).
 * The pure-function section is shared by the browser and node (verification
 * scripts).
 */
(function (global) {
'use strict';

/* ================= Constants (copied from the original constant table) ================= */

var COLORS = {
  sceneBg: 'rgb(250,250,250)',
  rectFill: 'rgb(225,233,242)',
  rectFillAbstract: 'rgb(226,242,226)',
  leafStroke: 'rgb(0,0,0)',
  rectStroke: 'rgb(120,140,160)',
  labelText: 'rgb(15,20,30)',
  labelAbstract: 'rgb(0,128,0)',
  labelCycle: 'rgb(180,0,0)',
  triangle: 'rgb(0,0,0)',
  triangleCycle: 'rgb(180,0,0)',
  cyclesTitle: 'rgb(120,0,0)',
  cyclesEntry: 'rgb(150,0,0)',
  tooltipCycle: 'rgb(180,0,0)',
  backEnabled: 'rgb(225,225,225)',
  backDisabled: 'rgb(205,205,205)',
  backTextDisabled: 'rgb(120,120,120)'
};

var SCENE_MIN_WIDTH = 1200;      // layout engine canvas width (rect coordinates are based on it)
var SCENE_SIDE_MARGIN = 24;      // racetrack-margin
var SCENE_BOTTOM_PADDING = 40;   // content height = max rect bottom + 40 + cycle list block
var CHAR_WIDTH = 7.0;            // 7px per character
var LABEL_LINE_HEIGHT = 14.0;    // label line height
var POPUP_LINE_HEIGHT = 16.0;    // dependency popup / cycle list line height
var TRIANGLE_SIDE = 12.0;
var TRIANGLE_HEIGHT = TRIANGLE_SIDE * 0.8660254037844386;
var NUB_WIDTH = 10.0;

/* ================= Label wrapping (ported from labels.clj) ================= */

// Prefer the break char (. - _ space) closest to the midpoint to split into
// two lines; hard-cut when no break char works.
var SPLIT_BREAK_CHARS = { '.': true, '-': true, '_': true, ' ': true };

function splitLabelLines(label, maxChars) {
  label = label || '';
  maxChars = Math.floor(maxChars || 0);
  var n = label.length;
  if (maxChars <= 0 || n <= maxChars) return [label];
  var target = Math.floor(n / 2);
  var best = null;
  for (var idx = 1; idx < n - 1; idx++) {
    var ch = label.charAt(idx);
    if (!SPLIT_BREAK_CHARS[ch]) continue;
    var cut = (ch === '-' || ch === '_') ? idx + 1 : idx;
    var left = label.substring(0, cut);
    var right = label.substring(cut).replace(/^[\./]+/, '');
    if (left.length <= maxChars && right.length <= maxChars &&
        left.trim() !== '' && right.trim() !== '') {
      var score = Math.abs(idx - target);
      if (!best || score < best.score) best = { left: left, right: right, score: score };
    }
  }
  if (!best) {
    var cut2 = Math.max(1, Math.min(n - 1, maxChars));
    best = { left: label.substring(0, cut2), right: label.substring(cut2) };
  }
  return [best.left.trim(), best.right.trim()];
}

/* ================= Scene model (pure functions, zero layout work) ================= */

// max-label-chars = (rect width - 12) / 7, lower bound 8
function maxLabelChars(rectWidth) {
  return Math.max(8, Math.floor((rectWidth - 12) / CHAR_WIDTH));
}

// buildSceneModel: flatten view JSON into a directly renderable scene model.
// view.nodes[].rect holds the real coordinates, used as-is;
// view.display_edges[].cycle_break drives triangle coloring and the red
// entries of the hover popup; view.cycle_lines is the aggregated bottom
// cycle list (own + descendant views, deduplicated on the Lua side).
// canvasWidth is the scene canvas width (default SCENE_MIN_WIDTH, the width
// the Lua layout engine computed rects for). Every layer group is centered on
// the layout canvas, so re-centering on a wider canvas is a uniform x shift
// of (canvasWidth - SCENE_MIN_WIDTH) / 2 — still zero layout work here.
function buildSceneModel(view, canvasWidth) {
  var nodes = view.nodes || [];
  var edges = view.display_edges || [];
  canvasWidth = Math.max(SCENE_MIN_WIDTH, canvasWidth || SCENE_MIN_WIDTH);
  var offsetX = (canvasWidth - SCENE_MIN_WIDTH) / 2;

  var fullNameById = {};
  nodes.forEach(function (node) {
    fullNameById[node.id] = node.full_name || node.id;
  });

  // Per node, per direction: "has any edge + has any cycle_break edge" plus
  // the deduplicated counterpart set for the hover popup.
  var incoming = {};  // id -> { any: true, cycle: true?, deps: {depId: cycleBreak} }
  var outgoing = {};
  edges.forEach(function (e) {
    var fb = !!e.cycle_break;
    var inc = incoming[e.to] || (incoming[e.to] = { any: false, cycle: false, deps: {} });
    inc.any = true; inc.cycle = inc.cycle || fb;
    inc.deps[e.from] = (inc.deps[e.from] || false) || fb;
    var out = outgoing[e.from] || (outgoing[e.from] = { any: false, cycle: false, deps: {} });
    out.any = true; out.cycle = out.cycle || fb;
    out.deps[e.to] = (out.deps[e.to] || false) || fb;
  });

  // Popup counterpart names drop the current view prefix (the original shows
  // full names, which never carry the project top namespace).
  var prefix = (view.key && view.key !== 'root') ? view.key + '.' : null;
  function depEntries(dir) {
    if (!dir) return [];
    return Object.keys(dir.deps).sort().map(function (depId) {
      var name = fullNameById[depId] || depId;
      if (prefix && name.indexOf(prefix) === 0 && name.length > prefix.length) {
        name = name.substring(prefix.length);
      }
      return { text: name, cycle: !!dir.deps[depId] };
    });
  }

  var rects = [];
  var maxRight = 0;
  var maxBottom = 0;
  nodes.forEach(function (node) {
    var rect = node.rect;
    if (!rect) return;
    var x = rect.x + offsetX, y = rect.y, w = rect.width, h = rect.height;
    var label = node.display_label || node.label || node.id;
    var cx = x + w / 2;
    var half = TRIANGLE_SIDE / 2;
    var inc = incoming[node.id];
    var out = outgoing[node.id];
    rects.push({
      id: node.id,
      node: node,
      x: x, y: y, width: w, height: h,
      label: label,
      labelLines: splitLabelLines(label, maxLabelChars(w)),
      labelX: cx,
      labelY: y + h / 2,
      fullName: node.full_name || node.id,
      leaf: !!node.leaf,
      abstract: !!node.abstract,
      drillable: !!node.drillable,
      // Red label: the node sits in a cycle of this view, or its subtree
      // contains one (both booleans are really filled by the Lua engine).
      cycleLabel: !!node.cycle || !!node.has_cycle_subtree,
      incoming: depEntries(inc),
      outgoing: depEntries(out),
      hasSource: typeof node.source_text === 'string' && node.source_text.length > 0,
      // Triangle indicators: at most one per direction; equilateral, side 12,
      // apex pointing down.
      inTriangle: (inc && inc.any) ? {
        points: [[cx - half, y], [cx + half, y], [cx, y + TRIANGLE_HEIGHT]],
        cycle: !!inc.cycle
      } : null,
      outTriangle: (out && out.any) ? {
        points: [[cx - half, y + h], [cx + half, y + h], [cx, y + h + TRIANGLE_HEIGHT]],
        cycle: !!out.cycle
      } : null
    });
    maxRight = Math.max(maxRight, x + w);
    maxBottom = Math.max(maxBottom, y + h);
  });

  // Bottom cycle list: "Cycles:" title 28px below the lowest rect, entries
  // every 16px; the block adds 28 + 20 + 16*n + 24 to the content height.
  var cycleLines = view.cycle_lines || [];
  var cyclesHeight = cycleLines.length > 0
    ? 28 + 20 + POPUP_LINE_HEIGHT * cycleLines.length + 24
    : 0;

  return {
    rects: rects,
    cycleLines: cycleLines,
    cyclesBaseY: maxBottom + 28,
    width: Math.max(canvasWidth, maxRight + SCENE_SIDE_MARGIN),
    height: maxBottom + SCENE_BOTTOM_PADDING + cyclesHeight
  };
}

// Clamp a popup rectangle into the viewport with a 6px margin.
function clampPopup(x, y, w, h, viewportWidth, viewportHeight) {
  var margin = 6;
  var maxX = viewportWidth - w - margin;
  var maxY = viewportHeight - h - margin;
  return [Math.max(margin, Math.min(x, maxX)), Math.max(margin, Math.min(y, maxY))];
}

/* ================= Exports (for node verification) ================= */

var ArchView = {
  COLORS: COLORS,
  SCENE_MIN_WIDTH: SCENE_MIN_WIDTH,
  SCENE_SIDE_MARGIN: SCENE_SIDE_MARGIN,
  SCENE_BOTTOM_PADDING: SCENE_BOTTOM_PADDING,
  CHAR_WIDTH: CHAR_WIDTH,
  LABEL_LINE_HEIGHT: LABEL_LINE_HEIGHT,
  POPUP_LINE_HEIGHT: POPUP_LINE_HEIGHT,
  TRIANGLE_SIDE: TRIANGLE_SIDE,
  TRIANGLE_HEIGHT: TRIANGLE_HEIGHT,
  NUB_WIDTH: NUB_WIDTH,
  splitLabelLines: splitLabelLines,
  maxLabelChars: maxLabelChars,
  buildSceneModel: buildSceneModel,
  clampPopup: clampPopup
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = ArchView;
}
global.ArchView = ArchView;

/* ================= UI (browser only) ================= */

if (typeof document === 'undefined') return;

var DATA = global.ARCH_VIEW_DATA;
var VIEWS = (DATA && DATA.views) || {};

var state = {
  navStack: ['root'],   // view key stack, bottom is always 'root'
  zoom: 1.0,            // CSS transform scale of the scene (no zoom-stack, #229)
  sceneWidth: 0,        // last rendered scene size, drives the stage box
  sceneHeight: 0,
  lastWidth: 0          // last viewport width; resize rebuilds on width change only
};

var els = {};

function currentViewKey() { return state.navStack[state.navStack.length - 1]; }

function svgEl(tag, attrs) {
  var el = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (var k in attrs) el.setAttribute(k, attrs[k]);
  return el;
}

function viewLabel(viewKey) {
  if (viewKey === 'root') return 'root';
  var parts = viewKey.split('.');
  return parts[parts.length - 1];
}

function drillableTarget(r) {
  // Drill-down target: the view for node.full_name exists and is non-empty
  if (!r.drillable) return null;
  var target = VIEWS[r.fullName];
  if (target && (target.nodes || []).length > 0) return r.fullName;
  return null;
}

// Scene canvas width follows the viewport (max(1200, viewport - 28), same as
// the original); a wider canvas re-centers every layer group.
function canvasWidthFor() {
  var viewport = (els.sceneScroll && els.sceneScroll.clientWidth) || global.innerWidth || SCENE_MIN_WIDTH;
  return Math.max(SCENE_MIN_WIDTH, viewport - 28);
}

function renderView() {
  var viewKey = currentViewKey();
  var view = VIEWS[viewKey];
  if (!view) { state.navStack = ['root']; viewKey = 'root'; view = VIEWS.root; }
  if (!view) return;
  hidePopups();
  renderToolbar();
  renderScene(buildSceneModel(view, canvasWidthFor()));
}

function renderToolbar() {
  // Back button: enabled gray 225 / disabled 205, text black / disabled (120,120,120)
  var canBack = state.navStack.length > 1;
  var parentKey = canBack ? state.navStack[state.navStack.length - 2] : null;
  els.backBtn.textContent = canBack ? 'Back: ' + viewLabel(parentKey) : 'Back';
  els.backBtn.disabled = !canBack;
  els.backBtn.style.background = canBack ? COLORS.backEnabled : COLORS.backDisabled;
  els.backBtn.style.color = canBack ? 'black' : COLORS.backTextDisabled;

  // Breadcrumb: last segment is the current view (plain bold text), the rest
  // are clickable and pop the stack
  els.breadcrumb.innerHTML = '';
  state.navStack.forEach(function (key, i) {
    if (i > 0) {
      var sep = document.createElement('span');
      sep.className = 'breadcrumb-sep';
      sep.textContent = ' / ';
      els.breadcrumb.appendChild(sep);
    }
    var isCurrent = i === state.navStack.length - 1;
    var item = document.createElement(isCurrent ? 'span' : 'a');
    item.textContent = viewLabel(key);
    if (isCurrent) {
      item.className = 'breadcrumb-current';
    } else {
      item.href = '#';
      item.addEventListener('click', function (ev) {
        ev.preventDefault();
        state.navStack = state.navStack.slice(0, i + 1);
        renderView();
        els.sceneScroll.scrollTop = 0;
      });
    }
    els.breadcrumb.appendChild(item);
  });
}

function renderScene(scene) {
  var svg = els.svg;
  svg.innerHTML = '';
  state.sceneWidth = scene.width;
  state.sceneHeight = Math.max(scene.height, 200);
  svg.setAttribute('width', state.sceneWidth);
  svg.setAttribute('height', state.sceneHeight);

  scene.rects.forEach(function (r) {
    var g = svgEl('g', { 'data-node': r.id });
    var fill = r.abstract ? COLORS.rectFillAbstract : COLORS.rectFill;
    var target = drillableTarget(r);
    if (target) {
      g.setAttribute('class', 'node-drillable');
    } else if (r.leaf && r.hasSource) {
      g.setAttribute('class', 'node-source');
    }

    // Rect: leaf stroke black 3px, non-leaf (120,140,160) 1px
    g.appendChild(svgEl('rect', {
      x: r.x, y: r.y, width: r.width, height: r.height,
      fill: fill,
      stroke: r.leaf ? COLORS.leafStroke : COLORS.rectStroke,
      'stroke-width': r.leaf ? 3 : 1
    }));

    // Non-leaf double nubs outside the left edge: width 10, height h/5, in
    // the [1/5,2/5] and [3/5,4/5] bands
    if (!r.leaf) {
      var nh = r.height / 5;
      g.appendChild(svgEl('rect', {
        x: r.x - NUB_WIDTH, y: r.y + nh, width: NUB_WIDTH, height: nh,
        fill: fill, stroke: COLORS.rectStroke, 'stroke-width': 1
      }));
      g.appendChild(svgEl('rect', {
        x: r.x - NUB_WIDTH, y: r.y + 3 * nh, width: NUB_WIDTH, height: nh,
        fill: fill, stroke: COLORS.rectStroke, 'stroke-width': 1
      }));
    }

    // Label: vertically centered, line height 14; red when the node sits in a
    // cycle or its subtree contains one (takes priority over abstract green)
    var labelColor = r.cycleLabel ? COLORS.labelCycle
      : (r.abstract ? COLORS.labelAbstract : COLORS.labelText);
    var mid = (r.labelLines.length - 1) / 2;
    r.labelLines.forEach(function (line, idx) {
      var t = svgEl('text', {
        x: r.labelX, y: r.labelY + (idx - mid) * LABEL_LINE_HEIGHT,
        'text-anchor': 'middle', 'dominant-baseline': 'central',
        'font-size': 12, 'font-family': 'monospace',
        fill: labelColor,
        'class': 'node-label'
      });
      t.textContent = line;
      g.appendChild(t);
    });

    // Click on a drillable node: push the nav stack and switch to the subview.
    // Non-drillable leaf with source: open the source modal. Anything else
    // (no drill target, no source) does nothing on click.
    if (target) {
      g.addEventListener('click', function () {
        state.navStack.push(target);
        renderView();
        els.sceneScroll.scrollTop = 0;
      });
    } else if (r.leaf && r.hasSource) {
      g.addEventListener('click', function () {
        openSourceModal(r.node);
      });
    }

    // Hover on the module name shows a single-line full-name tooltip
    g.addEventListener('mousemove', function (ev) {
      if (ev.target && ev.target.getAttribute && ev.target.getAttribute('class') === 'node-label') {
        showTextTooltip(r.fullName, ev.clientX, ev.clientY);
      } else {
        els.tooltip.style.display = 'none';
      }
    });
    g.addEventListener('mouseleave', hidePopups);
    svg.appendChild(g);
  });

  // Triangle indicators (no edge lines are drawn; a triangle turns red when
  // any edge in its direction has cycle_break=true). Hover pops the full
  // counterpart list of that direction.
  scene.rects.forEach(function (r) {
    [[r.inTriangle, r.incoming], [r.outTriangle, r.outgoing]].forEach(function (pair) {
      var tri = pair[0];
      if (!tri) return;
      svg.appendChild(svgEl('polygon', {
        points: tri.points.map(function (p) { return p.join(','); }).join(' '),
        fill: tri.cycle ? COLORS.triangleCycle : COLORS.triangle
      }));
      // Hit tolerance: an invisible triangle scaled 1.8x around the centroid
      // (the original allows a 5px tolerance around the edges)
      var cx = (tri.points[0][0] + tri.points[1][0] + tri.points[2][0]) / 3;
      var cy = (tri.points[0][1] + tri.points[1][1] + tri.points[2][1]) / 3;
      var hitPts = tri.points.map(function (p) {
        return (cx + (p[0] - cx) * 1.8) + ',' + (cy + (p[1] - cy) * 1.8);
      }).join(' ');
      var hit = svgEl('polygon', { points: hitPts, fill: 'rgba(0,0,0,0)' });
      hit.addEventListener('mousemove', function (ev) {
        showDepPopup(pair[1], ev.clientX, ev.clientY);
      });
      hit.addEventListener('mouseleave', hidePopups);
      svg.appendChild(hit);
    });
  });

  // Bottom cycle list: "Cycles:" title plus one "a->b->c->a" line per cycle
  if (scene.cycleLines.length > 0) {
    var title = svgEl('text', {
      x: 20, y: scene.cyclesBaseY, 'font-size': 12, 'font-family': 'monospace',
      fill: COLORS.cyclesTitle
    });
    title.textContent = 'Cycles:';
    svg.appendChild(title);
    scene.cycleLines.forEach(function (line, idx) {
      var t = svgEl('text', {
        x: 20, y: scene.cyclesBaseY + 20 + idx * POPUP_LINE_HEIGHT,
        'font-size': 12, 'font-family': 'monospace',
        fill: COLORS.cyclesEntry
      });
      t.textContent = line;
      svg.appendChild(t);
    });
  }
  applyZoom();
}

/* ---------- popup / tooltip ---------- */

function hidePopups() {
  els.popup.style.display = 'none';
  els.tooltip.style.display = 'none';
}

// Dependency popup: one row per counterpart (sorted, cycle rows red), sized
// 18 + 7*longest-row wide and at most max(60, viewport - 40) tall, placed at
// the cursor's lower right and clamped into the viewport.
function showDepPopup(entries, clientX, clientY) {
  els.tooltip.style.display = 'none';
  var popup = els.popup;
  popup.innerHTML = '';
  var maxLen = 0;
  entries.forEach(function (entry) {
    maxLen = Math.max(maxLen, entry.text.length);
    var row = document.createElement('div');
    row.textContent = entry.text;
    row.style.lineHeight = POPUP_LINE_HEIGHT + 'px';
    row.style.height = POPUP_LINE_HEIGHT + 'px';
    if (entry.cycle) row.style.color = COLORS.tooltipCycle;
    popup.appendChild(row);
  });
  var width = 18 + CHAR_WIDTH * maxLen;
  var maxHeight = Math.max(60, window.innerHeight - 40);
  var height = Math.min(10 + POPUP_LINE_HEIGHT * entries.length, maxHeight);
  popup.style.width = width + 'px';
  popup.style.height = height + 'px';
  var pos = clampPopup(clientX + 12, clientY + 12, width, height, window.innerWidth, window.innerHeight);
  popup.style.left = pos[0] + 'px';
  popup.style.top = pos[1] + 'px';
  popup.style.display = 'block';
}

// Single-line full-name tooltip: 12 + 7*chars wide, 20px tall, clamped.
function showTextTooltip(text, clientX, clientY) {
  els.popup.style.display = 'none';
  var tip = els.tooltip;
  tip.textContent = text;
  var width = 12 + CHAR_WIDTH * text.length;
  var height = 20;
  tip.style.width = width + 'px';
  tip.style.height = height + 'px';
  var pos = clampPopup(clientX + 12, clientY + 12, width, height, window.innerWidth, window.innerHeight);
  tip.style.left = pos[0] + 'px';
  tip.style.top = pos[1] + 'px';
  tip.style.display = 'block';
}

/* ---------- Source modal (in-page modal replaces the original Swing window) ---------- */

function openSourceModal(node) {
  els.modalTitle.textContent = node.full_name || node.id;
  els.modalBody.textContent = node.source_text || '(no source)';
  els.modal.style.display = 'flex';
}

function closeSourceModal() {
  els.modal.style.display = 'none';
}

/* ---------- Zoom (simplified: CSS transform, no cursor anchor / zoom-stack) ---------- */

function applyZoom() {
  var svg = els.svg;
  svg.style.transform = 'scale(' + state.zoom + ')';
  svg.style.transformOrigin = '0 0';
  // The stage box tracks the scaled size so native scrollbars stay correct;
  // CSS transform scales hit regions too, so hover/click stay aligned.
  els.stage.style.width = (state.sceneWidth * state.zoom) + 'px';
  els.stage.style.height = (state.sceneHeight * state.zoom) + 'px';
}

function zoomBy(factor) {
  state.zoom = Math.max(0.3, Math.min(4.0, state.zoom * factor));
  applyZoom();
}

/* ---------- Startup ---------- */

function init() {
  els.svg = document.getElementById('scene');
  els.stage = document.getElementById('stage');
  els.sceneScroll = document.getElementById('scene-scroll');
  els.backBtn = document.getElementById('back-btn');
  els.breadcrumb = document.getElementById('breadcrumb');
  els.popup = document.getElementById('dep-popup');
  els.tooltip = document.getElementById('name-tooltip');
  els.modal = document.getElementById('source-modal');
  els.modalTitle = document.getElementById('source-modal-title');
  els.modalBody = document.getElementById('source-modal-body');

  els.backBtn.addEventListener('click', function () {
    if (state.navStack.length > 1) {
      state.navStack.pop();
      renderView();
      els.sceneScroll.scrollTop = 0;
    }
  });

  // The popup is pointer-events:none (it must never swallow the hover that
  // opened it), so wheel scrolling is routed manually: while the dependency
  // popup is visible, the wheel scrolls it instead of the scene.
  document.addEventListener('wheel', function (ev) {
    if (els.popup.style.display === 'block') {
      els.popup.scrollTop += ev.deltaY;
      ev.preventDefault();
    }
  }, { passive: false });

  document.getElementById('zoom-in').addEventListener('click', function () { zoomBy(1.1); });
  document.getElementById('zoom-out').addEventListener('click', function () { zoomBy(1 / 1.1); });

  document.addEventListener('keydown', function (ev) {
    if (ev.key === 'Escape') { closeSourceModal(); return; }
    if (ev.key === '+' || ev.key === '=') zoomBy(1.1);
    if (ev.key === '-') zoomBy(1 / 1.1);
  });

  document.getElementById('source-modal-close').addEventListener('click', closeSourceModal);
  els.modal.addEventListener('click', function (ev) {
    if (ev.target === els.modal) closeSourceModal();
  });

  // Rebuild the scene only when the viewport WIDTH changes (matching the
  // original); height-only changes leave the scene alone.
  state.lastWidth = els.sceneScroll.clientWidth || global.innerWidth;
  var resizeTimer = null;
  global.addEventListener('resize', function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () {
      var width = els.sceneScroll.clientWidth || global.innerWidth;
      if (width !== state.lastWidth) {
        state.lastWidth = width;
        renderView();
      }
    }, 150);
  });

  renderView();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

})(typeof window !== 'undefined' ? window : globalThis);
