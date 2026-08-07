# Quality Gates

## Principle

Validation is selected by changed behavior, not by confidence or diff size. Passing compilation proves only that the
project builds; it does not prove playback, persistence, navigation or device behavior.

## Current executable entry points

The repository currently exposes these verified commands:

### Portable signing profile

For a portable working tree:

```powershell
./tools/check-signing-profile.ps1
```

Before committing, validate the staged representation:

```powershell
./tools/check-signing-profile.ps1 -Staged
git diff --cached -- build-profile.json5
```

A locally signed development profile is intentionally dirty and will not satisfy the portable-profile check. Never
sanitize or replace the user's local signing configuration unless commit preparation is explicitly requested.

### Build

```powershell
devecocli build
```

Set `DEVECO_SDK_HOME` as described in `../BUILDING.md`. Give synchronization and compilation enough time; an `EPIPE`
after an externally terminated process is not the underlying build result.

### Local and device tests

- Local Hypium tests are registered in `entry/src/test/List.test.ets`.
- Device tests are registered in `entry/src/ohosTest/ets/test/List.test.ets`.
- Prefer the externally registered Harmony Agent Tools MCP `harmony_project_run` operation `test-local` or
  `test-device`. Its result includes the actual Hypium summary; report the exact suite and target used.
- If MCP is unavailable, use `$env:HARMONY_AGENT_TOOLS_HOME\hdc-agent.cmd` from a separately installed checkout, or
  run the corresponding DevEco Studio test target.
- Do not substitute `devecocli build` for test execution.

### Device smoke test

With an already configured signed build and an authorized connected target:

Use the externally registered MCP: inspect the target/project with `harmony_inspect`, deploy with
`harmony_project_run`, capture with `harmony_capture`, and collect bounded diagnostics with `harmony_logs`. Select the
target explicitly when several devices are usable. The separately installed CLI fallback is
`$env:HARMONY_AGENT_TOOLS_HOME\hdc-agent.cmd`; it emits JSON and follows the same target-selection rules.

Raw `hdc` remains a fallback when an operation is not exposed. Neither MCP nor CLI uninstalls automatically. Do not
uninstall an application to resolve signing mismatch without approval.

## Required gates by change

| Change | Required automated validation | Additional validation |
| --- | --- | --- |
| Documentation only | Check links, paths, commands and internal consistency | No application build unless build behavior changed |
| ArkTS policy/model | Focused unit suite, adjacent suites, `devecocli build` | Manual check if framework behavior remains |
| Page/component UI | Relevant policy tests, `devecocli build` | Applicable UI matrix on available targets |
| Playback engine/runtime/session | Playback suites, `devecocli build` | Device playback, controls, background and logs |
| Import/metadata/artwork | Import/artwork suites, `devecocli build` | Relevant audio/file scenarios |
| Repository/schema/query | Repository suites, schema/version check, `devecocli build` | Fresh database; migration path when required |
| Resources or module/config | `devecocli build` | Launch and inspect affected resource/config behavior |
| Signing/build workflow | Portable guard and unsigned build | Restore local profile, signed build and device smoke when in scope |

When a focused suite cannot be invoked independently with available tooling, run its registered parent target and
state that limitation.

## Defect gate

A defect is complete only when:

- the invariant owner contains the fix;
- a regression test distinguishes the defect when feasible;
- adjacent behavior was checked;
- the required build succeeds;
- unavailable device or framework validation is explicitly reported.

## Static analysis

`code-linter.json5` defines the project lint policy, but this repository currently has no checked-in command wrapper
that agents can invoke consistently. Until that wrapper exists:

- use the DevEco Studio code linter when available;
- treat ArkTS compiler diagnostics from `devecocli build` as compilation validation, not as a lint substitute;
- report when lint was not runnable;
- do not invent or document an unverified CLI command.

## Planned automation contract

Future scripts should provide one stable entry point instead of requiring agents to rediscover commands. Reserve
these intended modes for `tools/verify.ps1`:

```powershell
./tools/verify.ps1 -Fast
./tools/verify.ps1 -Full
./tools/verify.ps1 -Device
```

Intended behavior:

- `Fast`: deterministic repository guards, lint when available, test-registration checks and local unit tests.
- `Full`: Fast plus the normal project build and all host-runnable tests.
- `Device`: Full plus selected device tests, install, launch and log collection.

Do not instruct agents to run these commands until the script exists. When implemented, the script becomes the
canonical source of command orchestration and this document should describe its supported parameters rather than
duplicating internals.

## Suggested repository guards

Add these incrementally:

- reject unregistered `*.test.ets` suites;
- reject AVPlayer construction outside PlaybackEngine;
- reject pages/components importing engine, session or relational data implementations;
- require a database version change when schema definitions change;
- validate referenced agent-document paths;
- detect committed local signing material;
- run the fastest deterministic guards in pull-request CI.

Full HarmonyOS builds require a Windows environment with the configured SDK. Use an appropriately provisioned runner
rather than weakening SDK or signing requirements.
