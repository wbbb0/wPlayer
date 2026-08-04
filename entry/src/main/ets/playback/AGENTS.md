# Playback Domain Instructions

Before changing playback behavior, read:

- `../../../../../docs/agents/ARCHITECTURE.md`
- `../../../../../docs/agents/CHANGE_WORKFLOW.md`
- `../../../../../docs/agents/QUALITY_GATES.md`
- `../../../../../docs/agents/TEST_MATRIX.md`

## Ownership

- PlaybackEngine exclusively owns AVPlayer lifecycle and raw state transitions.
- PlaybackRuntime is the unique application command facade and owns atomic queue and PlayerStore projection.
- PlaybackPersistenceCoordinator owns restore planning, playback preference writes and the ordered latest-wins
  pump for relational queue snapshots and cursor updates.
- PlaybackMediaCoordinator owns the shared track request epoch plus lyric and playback-artwork work.
- PlaybackPictureInPictureCoordinator owns PiP synchronization and lifecycle delegation.
- PlaybackAudioRecoveryCoordinator owns focus/output recovery intent and single-resume decisions.
- PlaybackSession owns AVSession and background-control integration.
- PlaybackQueue owns stable base-entry order, the active playback permutation, exact-entry cursor identity, repeat
  and shuffle invariants.
- PlayerStore exposes observable UI state and does not own AVPlayer operations.
- PlayerStore publishes the active playback order behind stable position slots. Pure permutations replace only the
  slot-to-entry projection and publish no LazyForEach operation; never publish reload or exchange storms for order
  changes. Structural queue changes use one slot reload, while cursor-only changes update only affected slots.
- Queue-page shuffle uses an exact immutable persistence request after the UI has acknowledged list unmount. Keep
  ordinary snapshot writes latest-wins, but preserve FIFO ordering around exact requests and resolve each exact
  receipt as persisted, failed or unavailable. Do not model this barrier as a general `flush()`.

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
