/* Pinned-layer viewer smoke test (arch_view #1), pure functions only — no
 * DOM stub. Covers the scene-model side of the mode:
 *   - an edge with direction_violation=true yields one red upward arrow from
 *     the depending node's top center to its target's bottom center
 *   - edges without the field (default mode data) yield no arrows
 *   - hover popup entries carry the violation flag per counterpart
 *   - arrowHeadPoints puts the tip on the segment end, pointing upward
 *
 * Run from the repository root:
 *   node tests/viewer_pinned_smoke.js
 * Exit code 0 = all checks passed.
 */
'use strict';

const path = require('path');
const ArchView = require(path.resolve(__dirname, '../viewer/script.js'));

let failures = 0;
function check(cond, label) {
  if (cond) {
    console.log('ok   ' + label);
  } else {
    failures += 1;
    console.log('FAIL ' + label);
  }
}

function rect(x, y) {
  return { x: x, y: y, width: 100, height: 70 };
}

// app pinned on top, ui below; ui->app is the upward violation edge.
const view = {
  key: 'root',
  nodes: [
    { id: 'app', full_name: 'app', rect: rect(550, 42) },
    { id: 'ui', full_name: 'ui', rect: rect(550, 147) },
  ],
  display_edges: [
    { from: 'ui', to: 'app', cycle_break: false, direction_violation: true },
  ],
  cycle_lines: [],
};

const scene = ArchView.buildSceneModel(view, ArchView.SCENE_MIN_WIDTH);

check(scene.violationArrows.length === 1, 'violation edge yields one arrow');
const arrow = scene.violationArrows[0];
check(arrow.from === 'ui' && arrow.to === 'app', 'arrow keeps the edge endpoints');
check(arrow.x1 === 600 && arrow.y1 === 147, 'arrow starts at the top center of the depending node');
check(arrow.x2 === 600 && arrow.y2 === 112, 'arrow ends at the bottom center of the target node');
check(arrow.y2 < arrow.y1, 'the arrow points upward');

const appRect = scene.rects.find((r) => r.id === 'app');
const uiRect = scene.rects.find((r) => r.id === 'ui');
check(appRect.incoming.length === 1 && appRect.incoming[0].violation === true,
  'incoming popup entry of the target is marked as a violation');
check(uiRect.outgoing.length === 1 && uiRect.outgoing[0].violation === true,
  'outgoing popup entry of the depending node is marked as a violation');
check(appRect.incoming[0].cycle === false, 'a violation is not a cycle_break');

// Default-mode data (no direction_violation field anywhere): no arrows, no
// violation flags — byte-identical rendering to the pre-#1 viewer.
const plainView = {
  key: 'root',
  nodes: view.nodes,
  display_edges: [{ from: 'ui', to: 'app', cycle_break: false }],
  cycle_lines: [],
};
const plainScene = ArchView.buildSceneModel(plainView, ArchView.SCENE_MIN_WIDTH);
check(plainScene.violationArrows.length === 0, 'default-mode data yields no arrows');
check(plainScene.rects.find((r) => r.id === 'app').incoming[0].violation === false,
  'default-mode popup entries carry no violation flag');

// Arrowhead geometry: tip at the segment end, base behind it, symmetric.
const head = ArchView.arrowHeadPoints(600, 147, 600, 112, 12, 10);
check(!!head && head[0][0] === 600 && head[0][1] === 112, 'arrowhead tip sits on the segment end');
check(Math.abs(head[1][1] - 124) < 1e-9 && Math.abs(head[2][1] - 124) < 1e-9,
  'arrowhead base sits 12px behind the tip (upward direction)');
const baseXs = [head[1][0], head[2][0]].sort((a, b) => a - b);
check(Math.abs(baseXs[0] - 595) < 1e-9 && Math.abs(baseXs[1] - 605) < 1e-9,
  'arrowhead base is 10px wide and symmetric');
check(ArchView.arrowHeadPoints(1, 2, 1, 2, 12, 10) === null,
  'a zero-length segment yields no arrowhead');

console.log(failures === 0
  ? 'viewer_pinned_smoke: all checks passed'
  : 'viewer_pinned_smoke: ' + failures + ' checks FAILED');
process.exit(failures === 0 ? 0 : 1);
