# Playback Domain Instructions

Before changing playback behavior, read:

- `../../../../../docs/agents/ARCHITECTURE.md`
- `../../../../../docs/agents/CHANGE_WORKFLOW.md`
- `../../../../../docs/agents/QUALITY_GATES.md`
- `../../../../../docs/agents/TEST_MATRIX.md`

## Ownership

- PlaybackEngine exclusively owns AVPlayer lifecycle and raw state transitions.
- PlaybackRuntime is the application coordinator and command facade.
- PlaybackSession owns AVSession and background-control integration.
- PlaybackQueue owns queue ordering, identity, cursor, repeat and shuffle invariants.
- PlayerStore exposes observable UI state and does not own AVPlayer operations.

## Stable state

The application-facing lifecycle is:

- idle
- loading
- ready
- playing
- paused
- completed
- error

Do not leak raw AVPlayer state names into UI policy. Do not call playback operations before AVPlayer reaches the
documented state required by that operation.

## Concurrency and lifecycle

- Invalidate superseded source loads and callbacks.
- A stale completion must not overwrite current state or release a current resource.
- Preserve play/pause intent during asynchronous source preparation.
- Release or reset resources when no longer needed.
- Do not destroy the application playback runtime because a page leaves navigation.

## Background behavior

- Keep AVSession metadata, playback state and position synchronized with PlaybackRuntime.
- Respond to supported system media controls.
- Start the long-running task only while eligible.
- Stop it when playback is stopped or no longer eligible.
- Do not add unrelated permissions.

## Verification

Playback changes require focused lifecycle/queue/session tests, adjacent playback suites and the normal build.
Device claims require actual playback, background/control checks and log inspection.
