# Test and Regression Matrix

## Async ownership regressions

- PlaybackCommandQueue: obsolete failures and queued commands cannot affect a newer source; active failures
  report once and do not block subsequent commands.
  Old-source cleanup failure during the next source's repository/authorization lookup preserves playback intent.
- PlaybackStopOperation: current stop failure rejects and reports ERROR without committing a clear/mode transition;
  obsolete failure and success cannot mutate a newer source, and a current success commits once.
- PlaybackSessionLifecycle: failed registration/activation, concurrent initialization, interrupted activation,
  failed deactivation and repeated shutdown all release owned resources.
- PlaybackLyricsReader: activation precedes source I/O, selection joins authorized prefetch, revoked access is
  retryable and never becomes cached absence.
- ImportUriAuthorization: restore only successfully activated existing URIs, preserve grants on cancellation or
  failed database updates. Device LibraryReadAuthorization verifies retained IDs, history, playlist links and
  unrelated unavailable/corrupt states against an isolated relational store.
- LibraryDetailRefreshCoordinator: retained-page reentry, active updates, changes during query, hidden/stale
  completion, query failure recovery and removed entities.
- Large queue restoration preserves duplicate occurrences and playback permutation with one lookup per unique
  track. Artwork cleanup tests retain an outside sentinel and use only an isolated fixture directory.

## Test registration

- Every local `*.test.ets` suite must be imported and invoked by `entry/src/test/List.test.ets`.
- Every device `*.test.ets` suite must be imported and invoked by
  `entry/src/ohosTest/ets/test/List.test.ets`.
- A new test file that is not registered is not test coverage.
- Keep tests deterministic and independent of execution order.
- Test externally meaningful invariants instead of reproducing implementation line by line.

## Change-to-test routing

| Changed area | Minimum regression coverage |
| --- | --- |
| Playback queue | build, empty/failure replacement, next/previous, repeat, shuffle, duplicates, insertion and removal |
| Playback lifecycle | rapid source replacement, loading intent, pause, completion, error, stale callback invalidation |
| Playback session/power | system commands, state/metadata synchronization, background eligibility and stop conditions |
| Library repository | initialization, queries, invalidation, paging, unavailable tracks and affected playlist projections |
| Import | cancellation, duplicate proof, permission loss, corrupt input, partial failure and session report continuity |
| Metadata/artwork | missing fields, extraction failure, embedded/large artwork, cache cleanup and stale work |
| Database schema | fresh creation, every supported incremental upgrade, rollback on migration failure and retained user data |
| M3U | encodings, malformed rows, duplicate rows, matching ambiguity, Unicode and round trip |
| Settings | corrupt/missing values, normalization, persistence and observable-store synchronization |
| Navigation | root selection, per-tab stacks, detail back behavior and breakpoint promotion/demotion |
| Detail collections | bounded previews, view-all routing, independent paging, selection and return-state continuity |
| Player gestures/morph | axis arbitration, thresholds, cancellation, frozen geometry, rapid input and final material handoff |

## UI manual matrix

For navigation and player UI changes, verify applicable scenarios on available targets:

- compact layout;
- unfolded portrait layout;
- unfolded landscape layout;
- system-bar, navigation-indicator and cutout avoidance;
- mini-player artwork and track-text taps;
- playback-control taps;
- horizontal dragging in both directions and elastic return;
- upward drag following the finger;
- below-threshold cancellation without overshoot;
- above-threshold expansion;
- full-player close and replacement-background handoff;
- rapid repeated open and close input;
- responsive breakpoint crossing while a secondary destination is active.

For API 26 appearance adaptation, also verify system light-sense settings and device material levels, settings
Toggle/Select, the seek Slider, menu/dialog/index popups and all sheet hosts. Check that detail-sheet content leaves
the native backing visible, artwork/active queue rows configured without shadows remain shadowless, and artwork
zoom retains detail. Repeat fallback checks on API 23; local shadow-policy tests do not prove native rendering.

Prefer the local Pura X Max emulator for repeatable wide-fold validation when a physical device is unavailable.

## Audio and file matrix

Consider the relevant subset:

- AAC in M4A;
- ALAC in M4A;
- MP3;
- FLAC;
- WAV;
- missing metadata;
- embedded artwork;
- large artwork;
- Unicode filenames and tags;
- corrupted files;
- moved or deleted files;
- revoked Picker authorization.

Additional playback scenarios:

- play, pause, seek, next and previous;
- shuffle and repeat modes;
- natural completion;
- rapid source switching;
- audio output disconnect/reconnect;
- background playback;
- lock-screen or system media controls;
- process termination and later library restoration where applicable.

## Claim discipline

- Do not claim an audio format works unless it was played on the named device or emulator.
- Do not claim background playback or system controls work based only on unit tests.
- Do not claim a gesture works based only on policy tests.
- Distinguish “not run”, “unavailable”, “failed” and “passed”.
- A build result is not a test result.
