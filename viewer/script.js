/* Arch View viewer — pure rendering layer.
 * Layout (Tarjan SCC / feedback edges / layering / coordinates) is computed
 * on the Lua side; this file does zero layout work: it directly consumes the
 * rect/layer of every view node and the cycle_break boolean of every view
 * edge in window.ARCH_VIEW_DATA.views.
 * The visual grammar (colors / geometry constants) is copied from
 * unclebob/arch-view; see monopoly research/unclebob-arch-view-visual-grammar.md.
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
  triangle: 'rgb(0,0,0)',
  triangleCycle: 'rgb(180,0,0)',
  backEnabled: 'rgb(225,225,225)',
  backDisabled: 'rgb(205,205,205)',
  backTextDisabled: 'rgb(120,120,120)',
  searchHighlight: 'rgb(255,140,0)'  // orange dashed frame for the search target (#230)
};

var SCENE_MIN_WIDTH = 1200;      // layout engine canvas width (rect coordinates are based on it)
var SCENE_SIDE_MARGIN = 24;      // racetrack-margin
var SCENE_BOTTOM_PADDING = 40;   // content height = max rect bottom + 40 (cycle list is #227, not included)
var CHAR_WIDTH = 7.0;            // 7px per character
var LABEL_LINE_HEIGHT = 14.0;    // label line height
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
// view.display_edges[].cycle_break drives triangle coloring.
function buildSceneModel(view) {
  var nodes = view.nodes || [];
  var edges = view.display_edges || [];

  // Per node, per direction: "has any edge + has any cycle_break edge"
  var incoming = {};  // id -> { any: true, cycle: true? }
  var outgoing = {};
  edges.forEach(function (e) {
    var fb = !!e.cycle_break;
    var inc = incoming[e.to] || (incoming[e.to] = { any: false, cycle: false });
    inc.any = true; inc.cycle = inc.cycle || fb;
    var out = outgoing[e.from] || (outgoing[e.from] = { any: false, cycle: false });
    out.any = true; out.cycle = out.cycle || fb;
  });

  var rects = [];
  var maxRight = 0;
  var maxBottom = 0;
  nodes.forEach(function (node) {
    var rect = node.rect;
    if (!rect) return;
    var x = rect.x, y = rect.y, w = rect.width, h = rect.height;
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

  return {
    rects: rects,
    width: Math.max(SCENE_MIN_WIDTH, maxRight + SCENE_SIDE_MARGIN),
    height: maxBottom + SCENE_BOTTOM_PADDING
  };
}

/* ================= Cross-view search (new feature, not in the original) ================= */

var SEARCH_RESULT_LIMIT = 30;

// searchNodes: case-insensitive substring match against every node's
// display_label / label / full_name / id across all views; results are
// ordered by view key and capped at SEARCH_RESULT_LIMIT.
function searchNodes(views, query) {
  query = (query || '').trim().toLowerCase();
  if (!query) return [];
  var results = [];
  Object.keys(views).sort().forEach(function (viewKey) {
    var nodes = (views[viewKey] && views[viewKey].nodes) || [];
    nodes.forEach(function (n) {
      var hay = [n.display_label, n.label, n.full_name, n.id]
        .filter(Boolean).join(' ').toLowerCase();
      if (hay.indexOf(query) >= 0) {
        results.push({
          viewKey: viewKey,
          nodeId: n.id,
          label: n.display_label || n.label || n.id,
          fullName: n.full_name || n.id
        });
      }
    });
  });
  return results.slice(0, SEARCH_RESULT_LIMIT);
}

// navPathTo: rebuild the root->target nav path from progressive key prefixes,
// keeping only prefixes that are real views. The result is equivalent to
// drilling down level by level, so Back walks back to root step by step.
function navPathTo(views, viewKey) {
  if (viewKey === 'root') return ['root'];
  var parts = viewKey.split('.');
  var path = ['root'];
  for (var i = 1; i <= parts.length; i++) {
    var key = parts.slice(0, i).join('.');
    if (views[key]) path.push(key);
  }
  return path;
}

/* ================= Exports (for node verification) ================= */

var ArchView = {
  COLORS: COLORS,
  SCENE_MIN_WIDTH: SCENE_MIN_WIDTH,
  SCENE_SIDE_MARGIN: SCENE_SIDE_MARGIN,
  SCENE_BOTTOM_PADDING: SCENE_BOTTOM_PADDING,
  CHAR_WIDTH: CHAR_WIDTH,
  LABEL_LINE_HEIGHT: LABEL_LINE_HEIGHT,
  TRIANGLE_SIDE: TRIANGLE_SIDE,
  TRIANGLE_HEIGHT: TRIANGLE_HEIGHT,
  NUB_WIDTH: NUB_WIDTH,
  splitLabelLines: splitLabelLines,
  maxLabelChars: maxLabelChars,
  buildSceneModel: buildSceneModel,
  SEARCH_RESULT_LIMIT: SEARCH_RESULT_LIMIT,
  searchNodes: searchNodes,
  navPathTo: navPathTo
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
  navStack: ['root'],  // view key stack, bottom is always 'root'
  highlight: null      // {viewKey, nodeId} set by search locate, cleared on navigation
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

function renderView() {
  var viewKey = currentViewKey();
  var view = VIEWS[viewKey];
  if (!view) { state.navStack = ['root']; viewKey = 'root'; view = VIEWS.root; }
  if (!view) return;
  renderToolbar();
  renderScene(viewKey, buildSceneModel(view));
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
        state.highlight = null;
        renderView();
        els.sceneScroll.scrollTop = 0;
      });
    }
    els.breadcrumb.appendChild(item);
  });
}

function renderScene(viewKey, scene) {
  var svg = els.svg;
  svg.innerHTML = '';
  svg.setAttribute('width', scene.width);
  svg.setAttribute('height', Math.max(scene.height, 200));

  scene.rects.forEach(function (r) {
    var g = svgEl('g', { 'data-node': r.id });
    var fill = r.abstract ? COLORS.rectFillAbstract : COLORS.rectFill;
    if (drillableTarget(r)) g.setAttribute('class', 'node-drillable');

    // Search locate highlight (new feature, not in the original): orange
    // dashed frame drawn 4px outside the node rect.
    if (state.highlight && state.highlight.viewKey === viewKey &&
        state.highlight.nodeId === r.id) {
      g.appendChild(svgEl('rect', {
        x: r.x - 4, y: r.y - 4, width: r.width + 8, height: r.height + 8,
        fill: 'none', stroke: COLORS.searchHighlight, 'stroke-width': 3,
        'stroke-dasharray': '6,3'
      }));
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

    // Label: vertically centered, line height 14
    var labelColor = r.abstract ? COLORS.labelAbstract : COLORS.labelText;
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

    // Click on a drillable node: push the nav stack and switch to the subview
    var target = drillableTarget(r);
    if (target) {
      g.addEventListener('click', function () {
        state.navStack.push(target);
        state.highlight = null;
        renderView();
        els.sceneScroll.scrollTop = 0;
      });
    }
    svg.appendChild(g);
  });

  // Triangle indicators (no edge lines are drawn; a triangle turns red when
  // any edge in its direction has cycle_break=true)
  scene.rects.forEach(function (r) {
    [r.inTriangle, r.outTriangle].forEach(function (tri) {
      if (!tri) return;
      svg.appendChild(svgEl('polygon', {
        points: tri.points.map(function (p) { return p.join(','); }).join(' '),
        fill: tri.cycle ? COLORS.triangleCycle : COLORS.triangle
      }));
    });
  });

  // Search locate: scroll the highlighted node into the visible area.
  if (state.highlight && state.highlight.viewKey === viewKey) {
    var located = null;
    scene.rects.forEach(function (r) { if (r.id === state.highlight.nodeId) located = r; });
    if (located) {
      setTimeout(function () {
        var viewportHeight = els.sceneScroll.clientHeight || 0;
        els.sceneScroll.scrollTop = Math.max(0, located.y - viewportHeight / 2);
      }, 0);
    }
  }
}

/* ---------- Search dropdown (new feature, not in the original) ---------- */

function renderSearchResults(results) {
  var dd = els.searchDropdown;
  dd.innerHTML = '';
  if (results.length === 0) { dd.style.display = 'none'; return; }
  results.forEach(function (r) {
    var item = document.createElement('div');
    item.className = 'search-item';
    item.textContent = r.label + '  —  ' + r.viewKey;
    // mousedown (not click) so the selection lands before the input's blur
    // hides the dropdown.
    item.addEventListener('mousedown', function (ev) {
      ev.preventDefault();
      state.navStack = navPathTo(VIEWS, r.viewKey);
      state.highlight = { viewKey: r.viewKey, nodeId: r.nodeId };
      dd.style.display = 'none';
      els.searchInput.blur();
      renderView();
    });
    dd.appendChild(item);
  });
  dd.style.display = 'block';
}

/* ---------- Startup ---------- */

function init() {
  els.svg = document.getElementById('scene');
  els.sceneScroll = document.getElementById('scene-scroll');
  els.backBtn = document.getElementById('back-btn');
  els.breadcrumb = document.getElementById('breadcrumb');
  els.searchInput = document.getElementById('search-input');
  els.searchDropdown = document.getElementById('search-dropdown');

  els.backBtn.addEventListener('click', function () {
    if (state.navStack.length > 1) {
      state.navStack.pop();
      state.highlight = null;
      renderView();
      els.sceneScroll.scrollTop = 0;
    }
  });

  els.searchInput.addEventListener('input', function () {
    renderSearchResults(searchNodes(VIEWS, els.searchInput.value));
  });
  els.searchInput.addEventListener('blur', function () {
    setTimeout(function () { els.searchDropdown.style.display = 'none'; }, 150);
  });
  els.searchInput.addEventListener('focus', function () {
    renderSearchResults(searchNodes(VIEWS, els.searchInput.value));
  });

  renderView();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}

})(typeof window !== 'undefined' ? window : globalThis);
