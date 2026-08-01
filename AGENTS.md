# wPlayer Agent Instructions

## Purpose

This repository contains a native HarmonyOS import-based local music player.

- Language: ArkTS
- UI: ArkUI with the Stage application model
- Primary module: `entry`
- Playback: Media Kit AVPlayer
- Metadata: AVMetadataExtractor plus documented format-specific fallbacks
- Background playback: AVSession Kit and Background Tasks Kit
- Persistence: ArkData relational store and Preferences

Keep the codebase cohesive and easy to change. Prefer fixing the owning abstraction over adding caller-specific
branches. Do not preserve a poor boundary merely to minimize the number of edited files.

## Instruction routing

Instructions are cumulative. This root file applies to the whole repository; the nearest nested `AGENTS.md` adds
rules for its directory.

Before editing, read the documents required by the affected area:

| Change area | Required documents |
| --- | --- |
| Any implementation change | `docs/agents/CHANGE_WORKFLOW.md`, `docs/agents/QUALITY_GATES.md` |
| Architecture, ownership, dependency direction | `docs/agents/ARCHITECTURE.md` |
| Navigation, pages, player UI, gestures, motion | `docs/agents/UI_CONTRACTS.md` |
| Tests or behavior with regression risk | `docs/agents/TEST_MATRIX.md` |
| Build environment or local signing | `docs/BUILDING.md` |
| Release build, release identity or publishing | `docs/RELEASING.md` |

Read the complete relevant document before acting. Do not rely on a remembered summary.

## Product boundaries

- Users import audio through the system Picker. Do not add unrestricted full-storage scanning unless explicitly
  requested and supported by the configured SDK.
- Retain access to original files through documented URI authorization. Do not copy music into the application
  sandbox unless managed imports are explicitly requested.
- Treat Picker URIs as authorization-managed resources. Never parse them to infer physical paths.
- Handle revoked authorization and moved, deleted or corrupt files.
- Do not request broad storage permissions when Picker access is sufficient.

## Architecture invariants

- Keep import, metadata, persistence, playback, background session, settings and UI responsibilities separated.
- Use one application-level PlaybackEngine and do not destroy it with page navigation.
- UI components must not create or own AVPlayer, AVSession, relational stores or file authorization.
- Pages and components read observable state and issue commands through application-level boundaries. They must not
  become alternative state owners.
- Fix behavior at the boundary that owns its invariant. Do not accumulate duplicated page conditionals, one-off
  overrides or compatibility branches.
- When the current structure prevents a clean fix, refactor the smallest coherent area and verify adjacent behavior.
- Search for the existing owner, policy, token, route or helper before introducing another definition.

The concrete dependency rules and current composition boundaries are defined in
`docs/agents/ARCHITECTURE.md`.

## Change workflow

Before editing:

1. Inspect `git status` and preserve unrelated user changes.
2. Read the applicable scoped instructions and agent documents.
3. Identify the behavior owner, invariant, callers and existing tests.
4. State the smallest coherent change and the adjacent behavior at risk.

While editing:

- Keep changed code cohesive and intentionally named.
- Prefer explicit state machines or phases over combinations of related booleans.
- Keep policy and computation independently testable when practical.
- Do not scatter magic values through Builders or lifecycle code.
- Do not add a new responsibility to an existing hotspot merely to keep the diff small.
- Do not perform opportunistic unrelated cleanup.

For a defect fix, add or update a regression test that demonstrates the broken invariant. If an automated test is
not feasible, document why and perform the narrowest relevant manual verification.

The full procedure is in `docs/agents/CHANGE_WORKFLOW.md`.

## HarmonyOS APIs

Before using an unfamiliar HarmonyOS API, search the official documentation:

```text
devecocli docs search <keywords...>
devecocli docs read "<documentId>"
```

Use the full document path returned by search. Do not invent APIs, decorators, permissions, imports, lifecycle
callbacks or `module.json5` fields.

- Respect the configured compatible and target SDK versions.
- Do not substitute Android, browser, Node.js or React APIs for HarmonyOS capabilities.
- Close file descriptors, extractors, players and other native resources according to documented lifecycles.
- Add only permissions required by the requested behavior.

## Data and media safety

- Every relational schema change must increment the database version.
- The application is publicly released. Every relational schema change must use a versioned incremental migration
  that preserves the existing music library and user data.
- Never delete, rebuild or silently replace an existing database to handle a schema-version mismatch. Unknown or
  unsupported versions must fail safely without modifying the database.
- Run each schema migration atomically. A migration failure must roll back and leave the previous schema and user
  data intact so a later application version can retry or recover.
- Import and sort-index progress and per-item outcomes are session-only observable state, not relational or
  Preferences data.
- Track records must retain enough information to detect duplicates and unavailable files.
- Do not store full artwork BLOBs in relational storage. Cache resized artwork in application storage.
- Do not assume AVMetadataExtractor exposes embedded lyrics. Sidecar LRC remains the primary lyric source.

## Validation

Choose validation from `docs/agents/QUALITY_GATES.md` and `docs/agents/TEST_MATRIX.md`.

Minimum rules:

- ArkTS, resource or configuration changes require the relevant automated tests and `devecocli build`.
- Defect fixes require regression coverage or an explicit explanation of the testing gap.
- Navigation and player UI changes require the applicable compact, unfolded, gesture and rapid-input checks.
- Media import, metadata and playback changes require only the relevant portions of the audio matrix; do not claim a
  format or device scenario works unless it was actually tested there.
- If a required device, emulator, SDK tool or test runner is unavailable, report that limitation rather than
  implying success.
- Prefer `tools/harmony-agent-tools/hdc-agent.cmd` for structured target discovery, touch, screenshots, build
  artifacts, install/start/stop and bounded logs; use raw HDC only when the wrapper does not expose the operation.

## Git and signing safety

- Do not discard unrelated changes.
- Do not commit, push, change signing configuration, change the bundle name or update SDK versions unless explicitly
  requested.
- Never commit signing passwords, private keys, certificate stores, provisioning profiles or machine-specific
  signing paths.
- Local DevEco signing intentionally makes the tracked root `build-profile.json5` dirty. Never hide it with
  `assume-unchanged`, `skip-worktree` or `.gitignore`.
- The committed portable profile must contain an empty `app.signingConfigs` and retain product mappings
  `default → default` and `release → release`.
- Before a commit, enable `.githooks`, run `./tools/check-signing-profile.ps1 -Staged`, and inspect the staged
  `build-profile.json5`.
- Never uninstall an existing application to resolve a signing mismatch without user approval; uninstalling deletes
  local application data.

Operational instructions belong in `docs/BUILDING.md` and `docs/RELEASING.md`, not in this root file.

## Documentation maintenance

- Keep one authoritative location for each procedure. Concise global safety constraints may be repeated, but link
  to the authoritative operational steps instead of copying them.
- Update architecture documents when an ownership or dependency invariant changes.
- Update quality gates when executable commands change.
- Update UI contracts only for intentional product behavior changes, not to rationalize a regression.
- Use current-state wording. Avoid stale phrases such as “when implemented” for features already present.
- Keep nested `AGENTS.md` files short and specific to their directory.

## Completion report

For implementation tasks, report:

- changed files;
- implementation summary;
- build result;
- automated and manual test results;
- known limitations or untested scenarios.

For review-only or documentation-only tasks, explicitly say that no application build or device test was run when
that is the case.
