# Test and Regression Matrix

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
