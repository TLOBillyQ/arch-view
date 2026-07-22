/* Node smoke test for the viewer's cross-view search (#230).
 *
 * Loads viewer/script.js with a minimal DOM stub and drives the real search
 * interaction: type a query, pick a dropdown result, then assert that
 *   - the nav stack equals manual drill-down to the same view,
 *   - the target node gets the orange dashed highlight frame,
 *   - the scene scrolls the target into view,
 *   - Back walks the stack back to root and clears the highlight,
 *   - empty / no-match queries hide the dropdown without navigating.
 *
 * Run from the repository root:
 *   node tests/viewer_search_smoke.js [data.js query viewKey nodeId]
 * With no arguments it uses the checked-in fixture golden data and searches
 * for node "strings" in view "util". Exit code 0 = all assertions passed.
 */
'use strict';

var fs = require('fs');
var path = require('path');

var DATA_PATH = process.argv[2] || 'tests/golden/viewer/architecture_data.js';
var QUERY = process.argv[3] || 'strings';
var EXPECT_VIEW = process.argv[4] || 'util';
var EXPECT_NODE = process.argv[5] || 'strings';

var failures = 0;
function check(cond, label) {
  if (cond) {
    console.log('ok   ' + label);
  } else {
    failures++;
    console.log('FAIL ' + label);
  }
}

/* ---------- Minimal DOM stub (only what viewer/script.js touches) ---------- */

function El(tag) {
  this.tagName = tag;
  this.children = [];
  this.attributes = {};
  this.style = {};
  this.listeners = {};
  this.textContent = '';
  this.className = '';
  this.disabled = false;
  this.scrollTop = 0;
  this.clientHeight = 0;
  this.value = '';
}
El.prototype.setAttribute = function (k, v) { this.attributes[k] = String(v); };
El.prototype.getAttribute = function (k) { return this.attributes[k]; };
El.prototype.appendChild = function (c) { this.children.push(c); return c; };
El.prototype.addEventListener = function (t, f) {
  (this.listeners[t] = this.listeners[t] || []).push(f);
};
El.prototype.dispatch = function (t, ev) {
  ev = ev || {};
  ev.preventDefault = ev.preventDefault || function () {};
  (this.listeners[t] || []).slice().forEach(function (f) { f(ev); });
};
El.prototype.blur = function () { this.dispatch('blur'); };
Object.defineProperty(El.prototype, 'innerHTML', {
  get: function () { return ''; },
  set: function () { this.children = []; }
});

var byId = {};
['scene', 'scene-scroll', 'back-btn', 'breadcrumb', 'search-input', 'search-dropdown']
  .forEach(function (id) { byId[id] = new El('div'); });
byId['scene-scroll'].clientHeight = 600;

global.window = global;
global.document = {
  readyState: 'complete',
  getElementById: function (id) { return byId[id]; },
  createElement: function (tag) { return new El(tag); },
  createElementNS: function (ns, tag) { return new El(tag); },
  addEventListener: function () {}
};
// Run deferred callbacks (scroll-into-view, dropdown hide) synchronously so
// assertions can run right after the dispatch that scheduled them.
global.setTimeout = function (fn) { fn(); return 0; };

/* ---------- Load real viewer data + the viewer script ---------- */

var dataSrc = fs.readFileSync(DATA_PATH, 'utf8');
eval(dataSrc); // sets window.ARCH_VIEW_DATA
var DATA = global.ARCH_VIEW_DATA;
var VIEWS = (DATA && DATA.views) || {};
check(Object.keys(VIEWS).length > 0, 'data loaded: views present (' + DATA_PATH + ')');
check(!!VIEWS[EXPECT_VIEW], 'expected view exists: ' + EXPECT_VIEW);

var ArchView = require(path.resolve('viewer/script.js'));

var els = {
  svg: byId.scene,
  sceneScroll: byId['scene-scroll'],
  backBtn: byId['back-btn'],
  breadcrumb: byId.breadcrumb,
  searchInput: byId['search-input'],
  searchDropdown: byId['search-dropdown']
};

/* ---------- Helpers to read the stub DOM ---------- */

function breadcrumbTexts() {
  return els.breadcrumb.children
    .filter(function (c) { return c.className !== 'breadcrumb-sep'; })
    .map(function (c) { return c.textContent; });
}

function findGroup(nodeId) {
  return els.svg.children.filter(function (c) {
    return c.tagName === 'g' && c.getAttribute('data-node') === nodeId;
  })[0] || null;
}

function highlightRects() {
  var out = [];
  els.svg.children.forEach(function (g) {
    (g.children || []).forEach(function (c) {
      if (c.getAttribute('stroke') === 'rgb(255,140,0)' &&
          c.getAttribute('stroke-dasharray') === '6,3') out.push(c);
    });
  });
  return out;
}

/* ---------- Pure functions ---------- */

check(ArchView.searchNodes(VIEWS, '').length === 0, 'empty query -> no results');
check(ArchView.searchNodes(VIEWS, '   ').length === 0, 'blank query -> no results');

var results = ArchView.searchNodes(VIEWS, QUERY);
check(results.length > 0, 'query "' + QUERY + '" matches (' + results.length + ' results)');
check(results.every(function (r) { return r.viewKey && r.nodeId && r.label; }),
  'every result carries viewKey/nodeId/label');
check(results.length <= ArchView.SEARCH_RESULT_LIMIT, 'results capped at limit');

var deepViews = { root: {}, a: {}, 'a.b': {}, 'a.b.c': {} };
check(JSON.stringify(ArchView.navPathTo(deepViews, 'a.b.c')) === JSON.stringify(['root', 'a', 'a.b', 'a.b.c']),
  'navPathTo keeps every existing prefix');
check(JSON.stringify(ArchView.navPathTo(deepViews, 'root')) === JSON.stringify(['root']),
  'navPathTo(root) stays at root');
var sparseViews = { root: {}, 'a.b.c': {} };
check(JSON.stringify(ArchView.navPathTo(sparseViews, 'a.b.c')) === JSON.stringify(['root', 'a.b.c']),
  'navPathTo skips missing intermediate views');

/* ---------- Interaction: type query, pick result ---------- */

check(els.svg.children.length > 0, 'initial render produced scene content');

els.searchInput.value = QUERY;
els.searchInput.dispatch('input');
check(els.searchDropdown.style.display === 'block', 'dropdown opens on matching input');
check(els.searchDropdown.children.length === results.length,
  'dropdown lists every result (' + results.length + ')');
check(els.searchDropdown.children[0].textContent.indexOf('—') > 0,
  'dropdown item shows "label — view path"');

var item = els.searchDropdown.children.filter(function (c) {
  return c.textContent.indexOf(EXPECT_VIEW) >= 0;
})[0];
check(!!item, 'dropdown contains a result in view ' + EXPECT_VIEW);
item.dispatch('mousedown');

check(els.searchDropdown.style.display === 'none', 'dropdown closes after selection');
var pathLabels = breadcrumbTexts();
var expectedLabels = ArchView.navPathTo(VIEWS, EXPECT_VIEW)
  .map(function (k) { return k === 'root' ? 'root' : k.split('.').pop(); });
check(JSON.stringify(pathLabels) === JSON.stringify(expectedLabels),
  'nav path rebuilt root->target: ' + pathLabels.join(' / '));

var hl = highlightRects();
check(hl.length === 1, 'target node has the orange dashed highlight frame');
var group = findGroup(EXPECT_NODE);
check(!!group && group.children.indexOf(hl[0]) >= 0,
  'highlight frame is drawn on node "' + EXPECT_NODE + '"');

var node = (VIEWS[EXPECT_VIEW].nodes || []).filter(function (n) {
  return n.id === EXPECT_NODE;
})[0];
var expectedScroll = Math.max(0, node.rect.y - 600 / 2);
check(els.sceneScroll.scrollTop === expectedScroll,
  'scene scrolled target into view (scrollTop=' + els.sceneScroll.scrollTop + ')');

/* ---------- Back equivalence + highlight clearing ---------- */

var depth = expectedLabels.length;
for (var i = 0; i < depth - 1; i++) {
  els.backBtn.dispatch('click');
}
check(JSON.stringify(breadcrumbTexts()) === JSON.stringify(['root']),
  'Back walks the stack back to root step by step');
check(els.backBtn.disabled === true, 'Back disabled at root');
check(highlightRects().length === 0, 'highlight cleared after navigating away');

/* ---------- Drill-down equals search navigation ---------- */

// Click through every intermediate view level by level, exactly as a user
// would; the resulting breadcrumb must equal the search-built nav path.
var navKeys = ArchView.navPathTo(VIEWS, EXPECT_VIEW);
for (var lvl = 1; lvl < navKeys.length; lvl++) {
  var segment = navKeys[lvl].split('.').pop();
  var drillGroup = findGroup(segment);
  check(!!drillGroup, 'view ' + navKeys[lvl - 1] + ' shows drillable node "' + segment + '"');
  drillGroup.dispatch('click');
}
check(JSON.stringify(breadcrumbTexts()) === JSON.stringify(expectedLabels),
  'manual drill-down produces the same nav path as search');
check(highlightRects().length === 0, 'drill-down does not highlight');

/* ---------- No-result behavior ---------- */

els.searchInput.value = 'zzz-no-such-module';
els.searchInput.dispatch('input');
check(els.searchDropdown.style.display === 'none', 'no match -> dropdown stays hidden');
check(JSON.stringify(breadcrumbTexts()) === JSON.stringify(expectedLabels),
  'no match -> no navigation');

if (failures > 0) {
  console.error('viewer_search_smoke: ' + failures + ' assertion(s) failed');
  process.exit(1);
}
console.log('viewer_search_smoke: all assertions passed');
