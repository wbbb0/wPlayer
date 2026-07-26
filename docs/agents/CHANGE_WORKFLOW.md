# Change Workflow

## Goal

Make the smallest coherent change that restores or adds a clearly owned invariant. A small diff is not automatically
a clean change, and a refactor is not automatically safer because it is broad.

## 1. Establish the working state

Before editing:

1. Run `git status --short`.
2. Treat every existing modification as user-owned unless proven otherwise.
3. Read the root and nearest scoped agent instructions.
4. Read the agent documents routed by the root instructions.
5. Inspect the affected implementation, its callers and relevant tests.

Do not discard, overwrite, reformat or stage unrelated work.

## 2. Define the change

Write down, at least mentally:

- observed behavior;
- expected behavior;
- owning abstraction;
- violated or new invariant;
- affected callers and state consumers;
- asynchronous, persistence, navigation and lifecycle risks;
- evidence that will demonstrate completion.

If the proposed fix belongs in a page but the invariant is shared by multiple consumers, stop and find the shared
owner.

## 3. Search before adding

Before adding a new helper, token, route, policy, state field or compatibility branch, search for:

- an existing canonical implementation;
- similar naming in adjacent domains;
- current tests that already encode the behavior;
- call sites that would remain inconsistent;
- comments or workarounds describing the same problem.

Extend the existing owner when it remains cohesive. Extract a new owner when the existing type would gain another
independent reason to change.

## 4. Regression-first defect repair

For a defect:

1. Add or update a test that exercises the broken invariant.
2. Confirm it would distinguish the old behavior from the fix when practical.
3. Fix the owning abstraction.
4. Run the focused test and adjacent tests.
5. Run the broader gate required by `QUALITY_GATES.md`.

Do not assert that a regression test failed before the fix unless it was actually run against the broken state.
When framework-only behavior cannot be automated, isolate as much policy as possible and record the remaining manual
check.

## 5. Implementation rules

- Keep one authoritative state owner.
- Prefer pure policy functions or small state machines for decisions with meaningful edge cases.
- Use explicit enum phases for multi-stage transitions.
- Use completion callbacks for animation sequencing; do not coordinate stages with unguarded `setTimeout`.
- Invalidate stale asynchronous completions.
- Keep geometry in frame or point objects and motion constants in specification types.
- Prefer render transforms for frame-by-frame interaction.
- Preserve resource ownership and close resources on all terminal paths.
- Avoid temporary branches with no removal condition.
- Avoid comments that restate code; document invariants, external constraints and non-obvious lifecycle reasons.

## 6. Hotspot growth policy

Large files are risk indicators, not automatic defects. Do not split files mechanically by line count.

When touching an existing hotspot:

- do not add another independent responsibility;
- extract a cohesive policy, data source, coordinator or adapter when the change reveals a stable boundary;
- keep state that must transition atomically together;
- retain behavior with focused tests before and after extraction;
- avoid repository-wide rewrites unless the requested outcome requires them.

New files should have a single describable responsibility. If a new type immediately requires unrelated lifecycle,
persistence, rendering and policy concerns, revise the boundary before continuing.

## 7. Adjacent verification

Verify consumers of the changed invariant, not only the edited function.

Examples:

- queue changes: next, previous, repeat, shuffle, duplicate identities and current-item continuity;
- playback source changes: rapid replacement, pause while loading, completion and errors;
- repository changes: invalidation, empty results, paging, playlist projections and database lifecycle;
- import changes: duplicate proof, cancellation, corrupt files, permissions and operation reports;
- responsive UI changes: both navigation hosts, promotion/demotion, back behavior and preserved state;
- morph changes: opening, cancellation, closing, rapid repeated input and HDS material handoff.

Use `TEST_MATRIX.md` for the full routing table.

## 8. Finish cleanly

Before reporting completion:

1. Inspect the final diff.
2. Confirm no unrelated changes were introduced.
3. Confirm temporary logging, debug paths and duplicated compatibility logic are absent.
4. Run the required quality gates.
5. Report exactly what ran, what passed and what was unavailable.
6. List known limitations without claiming untested behavior.
