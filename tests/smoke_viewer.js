/* Viewer interaction smoke test on a minimal DOM stub (no browser).
 * Covers the monopoly #229 interactions in viewer/script.js:
 *   - clicking a leaf node with source_text opens the source modal
 *     (and Close button / backdrop click / Escape close it)
 *   - clicking a node that is neither drillable nor source-backed does nothing
 *   - +/- keys zoom the scene via CSS transform and clicks still land
 *   - a viewport WIDTH change rebuilds the scene re-centered; height-only
 *     changes do not rebuild
 * Plus the code-review fixes on the #227/#229/#230 merge:
 *   - zoom keys are ignored while typing in the search input (or any
 *     input/textarea)
 *   - Escape also hides the dependency popup / tooltip
 *   - the wheel scrolls the popup only while it is shown by a triangle hover
 *
 * Run from the repository root:
 *   node tests/smoke_viewer.js [path/to/architecture_data.js]
 * Defaults to the golden fixture data. Exit code 0 = all checks passed.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DATA_PATH = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.resolve(__dirname, 'golden/viewer/architecture_data.js');

let failures = 0;
function check(cond, label) {
  if (cond) {
    console.log('ok   ' + label);
  } else {
    failures += 1;
    console.log('FAIL ' + label);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/* ---------- Minimal DOM stub ---------- */

function makeEl(tag) {
  const el = {
    tagName: tag,
    children: [],
    attrs: {},
    listeners: {},
    style: {},
    textContent: '',
    className: '',
    disabled: false,
    href: '',
    scrollTop: 0,
    clientWidth: 0,
    renderCount: 0,
    setAttribute(k, v) { this.attrs[k] = String(v); },
    getAttribute(k) { return this.attrs[k] !== undefined ? this.attrs[k] : null; },
    appendChild(c) { this.children.push(c); return c; },
    addEventListener(type, fn) {
      (this.listeners[type] = this.listeners[type] || []).push(fn);
    },
    dispatch(type, ev) {
      ev = ev || {};
      if (!ev.target) ev.target = this;
      ev.preventDefault = ev.preventDefault || function () {};
      (this.listeners[type] || []).slice().forEach((fn) => fn(ev));
    },
  };
  // script.js clears elements with `el.innerHTML = ''` before re-rendering;
  // count those sets to detect scene rebuilds.
  Object.defineProperty(el, 'innerHTML', {
    set() { this.children = []; this.renderCount += 1; },
    get() { return ''; },
  });
  return el;
}

const ids = {};
[
  'scene', 'stage', 'scene-scroll', 'back-btn', 'breadcrumb',
  'source-modal', 'source-modal-title', 'source-modal-body',
  'zoom-in', 'zoom-out', 'source-modal-close',
  'dep-popup', 'name-tooltip',
  'search-input', 'search-dropdown',
].forEach((id) => { ids[id] = makeEl(id); });
ids['scene-scroll'].clientWidth = 1200;

const docListeners = {};
const winListeners = {};

global.window = global;
global.innerWidth = 1200;
global.addEventListener = function (type, fn) {
  (winListeners[type] = winListeners[type] || []).push(fn);
};
global.document = {
  readyState: 'complete',
  getElementById: (id) => ids[id] || null,
  createElementNS: (ns, tag) => makeEl(tag),
  createElement: (tag) => makeEl(tag),
  addEventListener(type, fn) {
    (docListeners[type] = docListeners[type] || []).push(fn);
  },
};

function fireDocument(type, ev) {
  (docListeners[type] || []).slice().forEach((fn) => fn(ev || {}));
}
function fireWindow(type, ev) {
  (winListeners[type] || []).slice().forEach((fn) => fn(ev || {}));
}

/* ---------- Test data ---------- */

// architecture_data.js is `window.ARCH_VIEW_DATA = {...}`; evaluate it.
new Function(fs.readFileSync(DATA_PATH, 'utf8'))();
const VIEWS = global.ARCH_VIEW_DATA.views;

function leafNodes(viewKey) {
  return (VIEWS[viewKey].nodes || []).filter((n) => n.leaf && !n.drillable);
}

// A view deep enough to have leaves, with at least two of them (one is
// stripped of source to stand in for a "no source" node).
const viewKeys = Object.keys(VIEWS).filter((k) => k !== 'root').sort();
const targetViewKey = viewKeys.find((k) => leafNodes(k).length >= 2) || viewKeys[0];
if (!targetViewKey) {
  console.log('FAIL no non-root view in data');
  process.exit(1);
}
const leaves = leafNodes(targetViewKey);
const sourceLeaf = leaves.find((n) => typeof n.source_text === 'string' && n.source_text.length > 0);
const noSourceLeaf = leaves.find((n) => n !== sourceLeaf);
if (!sourceLeaf || !noSourceLeaf) {
  console.log('FAIL need at least two leaf nodes in view ' + targetViewKey);
  process.exit(1);
}
// Simulate a node with no source at all: clicks on it must do nothing.
noSourceLeaf.source_text = '';

/* ---------- Load the viewer (runs init immediately) ---------- */

require(path.resolve(__dirname, '../viewer/script.js'));

function groups() {
  return ids.scene.children.filter((c) => c.tagName === 'g');
}
function groupById(id) {
  return groups().find((g) => g.attrs['data-node'] === id);
}
function drillTo(viewKey) {
  viewKey.split('.').forEach((seg) => {
    const g = groupById(seg);
    if (!g) throw new Error('no group for segment ' + seg + ' on the way to ' + viewKey);
    g.dispatch('click');
  });
}

async function main() {
  // --- Drill-down still works, then leaves are clickable ---
  drillTo(targetViewKey);
  check(ids['back-btn'].disabled === false, 'drill-down enables the Back button');

  const sourceGroup = groupById(sourceLeaf.id);
  check(!!sourceGroup, 'leaf node with source is rendered in view ' + targetViewKey);
  check(sourceGroup.attrs['class'] === 'node-source', 'source leaf carries the node-source class');

  // --- Source modal: open + three close paths ---
  sourceGroup.dispatch('click');
  check(ids['source-modal'].style.display === 'flex', 'clicking a source leaf opens the modal');
  check(ids['source-modal-title'].textContent === (sourceLeaf.full_name || sourceLeaf.id),
    'modal title shows the node full name');
  check(ids['source-modal-body'].textContent === sourceLeaf.source_text,
    'modal body shows the raw source_text');

  ids['source-modal-close'].dispatch('click');
  check(ids['source-modal'].style.display === 'none', 'Close button closes the modal');

  sourceGroup.dispatch('click');
  ids['source-modal'].dispatch('click', { target: ids['source-modal'] });
  check(ids['source-modal'].style.display === 'none', 'backdrop click closes the modal');

  sourceGroup.dispatch('click');
  fireDocument('keydown', { key: 'Escape' });
  check(ids['source-modal'].style.display === 'none', 'Escape closes the modal');

  // --- Node with neither drill target nor source: click does nothing ---
  const noSourceGroup = groupById(noSourceLeaf.id);
  check(!!noSourceGroup && noSourceGroup.attrs['class'] === undefined,
    'plain leaf carries no interactive class');
  noSourceGroup.dispatch('click');
  check(ids['source-modal'].style.display !== 'flex', 'clicking a source-less leaf opens nothing');

  // --- Zoom via +/- keys ---
  check(ids.scene.style.transform === 'scale(1)', 'initial zoom is scale(1)');
  fireDocument('keydown', { key: '+' });
  check(ids.scene.style.transform === 'scale(1.1)', '+ key zooms in to scale(1.1)');
  const sceneWidth = parseFloat(ids.scene.attrs.width);
  check(Math.abs(parseFloat(ids.stage.style.width) - sceneWidth * 1.1) < 0.001,
    'stage box tracks the zoomed scene width');
  fireDocument('keydown', { key: '=' });
  check(ids.scene.style.transform.indexOf('scale(1.21') === 0, '= key also zooms in');
  fireDocument('keydown', { key: '-' });
  fireDocument('keydown', { key: '-' });
  check(ids.scene.style.transform === 'scale(1)', '- key zooms back out');

  // --- Zoom keys are ignored while typing in a text field ---
  fireDocument('keydown', { key: '+', target: ids['search-input'] });
  check(ids.scene.style.transform === 'scale(1)', '+ typed in the search input does not zoom');
  fireDocument('keydown', { key: '=', target: ids['search-input'] });
  check(ids.scene.style.transform === 'scale(1)', '= typed in the search input does not zoom');
  fireDocument('keydown', { key: '-', target: { tagName: 'textarea' } });
  check(ids.scene.style.transform === 'scale(1)', 'zoom keys are ignored from any input/textarea');

  for (let i = 0; i < 40; i++) fireDocument('keydown', { key: '-' });
  check(ids.scene.style.transform === 'scale(0.3)', 'zoom is clamped at 0.3');
  fireDocument('keydown', { key: '+' }); // back above the floor for the next checks
  ids['zoom-in'].dispatch('click');
  check(ids.scene.style.transform.indexOf('scale(0.363') === 0, 'zoom-in button zooms in');
  ids['zoom-out'].dispatch('click');
  ids['zoom-out'].dispatch('click');

  // Clicks still land after zooming (CSS transform scales hit regions).
  fireDocument('keydown', { key: '+' });
  sourceGroup.dispatch('click');
  check(ids['source-modal'].style.display === 'flex', 'click still opens the modal while zoomed');
  fireDocument('keydown', { key: 'Escape' });
  fireDocument('keydown', { key: '-' });

  // --- Popup: triangle-hover wheel routing + Escape hides popups ---
  const hitTri = ids.scene.children.find(
    (c) => c.tagName === 'polygon' && c.attrs.fill === 'rgba(0,0,0,0)');
  check(!!hitTri, 'view ' + targetViewKey + ' renders triangle hit areas');
  hitTri.dispatch('mousemove', { clientX: 100, clientY: 100 });
  check(ids['dep-popup'].style.display === 'block', 'triangle hover shows the dependency popup');

  let prevented = 0;
  fireDocument('wheel', { deltaY: 120, preventDefault() { prevented += 1; } });
  check(ids['dep-popup'].scrollTop === 120 && prevented === 1,
    'wheel over a triangle-hover popup scrolls the popup, not the scene');

  fireDocument('keydown', { key: 'Escape' });
  check(ids['dep-popup'].style.display === 'none' && ids['name-tooltip'].style.display === 'none',
    'Escape also hides the popup and the tooltip');

  // Hover off the triangle (popup hidden): the wheel is not hijacked.
  prevented = 0;
  fireDocument('wheel', { deltaY: 120, preventDefault() { prevented += 1; } });
  check(prevented === 0, 'wheel with the popup hidden keeps scrolling the scene');

  // Popup visible but not opened by a triangle hover: still not hijacked.
  ids['dep-popup'].style.display = 'block';
  prevented = 0;
  fireDocument('wheel', { deltaY: 120, preventDefault() { prevented += 1; } });
  check(prevented === 0, 'wheel is not routed to a popup not opened by triangle hover');
  ids['dep-popup'].style.display = 'none';

  // --- Resize: width change rebuilds re-centered; height-only does not ---
  const rectXBefore = parseFloat(groupById(sourceLeaf.id).children[0].attrs.x);
  const rendersBefore = ids.scene.renderCount;
  ids['scene-scroll'].clientWidth = 1600;
  fireWindow('resize');
  await sleep(250);
  check(ids.scene.renderCount === rendersBefore + 1, 'width change rebuilds the scene once');
  check(ids.scene.attrs.width === String(1572), 'scene canvas follows viewport width (1600 - 28)');
  const rectXAfter = parseFloat(groupById(sourceLeaf.id).children[0].attrs.x);
  check(Math.abs(rectXAfter - rectXBefore - (1572 - 1200) / 2) < 0.001,
    'layer groups re-center on the wider canvas (uniform shift)');

  const rendersAfterWidth = ids.scene.renderCount;
  fireWindow('resize'); // same width, only the (unstubbed) height would differ
  await sleep(250);
  check(ids.scene.renderCount === rendersAfterWidth, 'height-only resize does not rebuild');

  console.log(failures === 0
    ? 'smoke_viewer: all checks passed'
    : 'smoke_viewer: ' + failures + ' checks FAILED');
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
