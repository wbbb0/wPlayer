const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
// Replay SDK-generated update callbacks; this is not a native ArkUI runtime test.
if (!process.argv[2] || !process.argv[3]) {
  throw new Error('Usage: node tools/verify-mini-player-rendering.cjs <compiled MiniPlayerTrackPager.ts> <TypeScript module path>');
}
const ts = require(process.argv[3]);
const source = fs.readFileSync(process.argv[2], 'utf8').replace(/^import .*;\r?\n/gm, '');
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS } }).outputText;
let currentId = 0;
let nextId = 1;
let branchParent = 0;
const observers = new Map();
const branches = new Map();
const texts = new Map();
class ViewPU {
  observeComponentCreation2(callback, type) {
    const id = nextId++;
    observers.set(id, { callback, type, parent: branchParent });
    const previous = currentId;
    currentId = id;
    callback(id, true);
    currentId = previous;
  }
  ifElseBranchUpdateFunction(branch, build) {
    if (branches.get(currentId) === branch) return;
    const descendants = new Set([currentId]);
    for (const [id, observer] of observers) {
      if (descendants.has(observer.parent)) descendants.add(id);
    }
    descendants.delete(currentId);
    for (const id of descendants) {
      observers.delete(id); texts.delete(id); branches.delete(id);
    }
    branches.set(currentId, branch);
    const previous = branchParent;
    branchParent = currentId;
    build();
    branchParent = previous;
  }
  finalizeConstruction() {}
}
class Property {
  constructor(value) { this.value = value; }
  get() { return this.value; }
  set(value) { this.value = value; }
}
const component = (text = false) => new Proxy({}, {
  get(_target, key) {
    return key === 'create' && text ? value => texts.set(currentId, value) : () => {};
  }
});
const exportsObject = {};
vm.runInNewContext(js, {
  exports: exportsObject, ViewPU, SynchedPropertyNesedObjectPU: Property,
  SynchedPropertySimpleOneWayPU: Property,
  Column: component(), Row: component(), Text: component(true), If: component(),
  HorizontalAlign: { Start: 0 }, FlexAlign: { Center: 0 }, FontWeight: { Medium: 0 },
  TextOverflow: { Ellipsis: 0 },
  MiniPlayerTrackPageTarget: { CURRENT: 0, PREVIOUS: 1, NEXT: 2 }
});
const entry = id => ({ queueEntryId: id, track: { title: `Title ${id}`, artistDisplay: `Artist ${id}` } });
const binding = { trackPagerActive: true, trackPagerViewportWidth: 180, offsetX: 0 };
const pager = new exportsObject.MiniPlayerTrackPager(null, { playerStore: {}, binding, marqueeActive: true, followsSwipeOffset: true });
const setWindow = (previous, current, next) => {
  binding.trackPagerPrevious = previous === undefined ? undefined : entry(previous);
  binding.trackPagerCurrent = entry(current);
  binding.trackPagerNext = next === undefined ? undefined : entry(next);
};
const values = () => [...texts.entries()].sort((a, b) =>
  observers.get(a[0]).parent - observers.get(b[0]).parent || a[0] - b[0]).map(pair => pair[1]);
setWindow(10, 20, 30);
pager.FrozenPages();
assert.deepEqual(values(), ['Title 10', 'Artist 10', 'Title 20', 'Artist 20', 'Title 30', 'Artist 30']);
let checks = 0;
for (const window of [[20, 30, 40], [30, 40, 50], [20, 30, 40], [undefined, 10, 20], [10, 20, undefined], [20, 30, 40]]) {
  setWindow(...window);
  for (const [id, observer] of [...observers]) {
    if (!observers.has(id)) continue;
    currentId = id;
    observer.callback(id, false);
  }
  const expected = window.flatMap(id => id === undefined ? [] : [`Title ${id}`, `Artist ${id}`]);
  assert.deepEqual(values(), expected, `stale or misplaced title/artist after window ${window}`);
  checks++;
}
console.log(`PASS ${checks} compiled rendering regressions: forward, reversal, missing/reappearing neighbors`);
