# Harmony Agent Tools

`harmony-agent-tools` is a self-contained PowerShell 5.1-compatible wrapper around official HarmonyOS command-line
tools. It is designed for coding agents and intentionally avoids importing application source or build
configuration so the directory can later become a standalone repository.

## Goals

- make device selection explicit and safe when several targets are connected;
- map running DevEco emulator names to their HDC targets;
- provide simple touch, wait and screenshot commands;
- capture animation frames at specific offsets while a gesture is still running;
- return machine-readable JSON with absolute image paths;
- wrap build, install, normal launch and debug launch without automatically uninstalling applications;
- expose bounded application logs and machine-readable environment diagnostics;
- keep project-specific bundle names, abilities, artifact paths and coordinates outside the module.

## Entry point

When local PowerShell policy allows scripts:

```powershell
./tools/harmony-agent-tools/hdc-agent.ps1 targets
```

On Windows, the command shim avoids changing the user or machine execution policy:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd targets
```

Every successful command writes JSON to stdout. Errors go to stderr and produce a non-zero exit code.

## Device selection

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd targets
```

When more than one usable target is connected, all device-changing or capture commands require `-Target`:

```powershell
-Target 127.0.0.1:5555
```

The wrapper does not guess between connected devices.

On Windows, map running DevEco emulator names to HDC targets:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd emulators
```

This removes the need to correlate `Emulator.exe` process arguments and listening ports manually.

All target-bound commands can select a running DevEco emulator by exact name instead of copying its dynamic port:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd screenshot `
  -EmulatorName "Pura 90" `
  -OutputPath ./tools/harmony-agent-tools/artifacts/pura-90.jpeg
```

`-Target` and `-EmulatorName` are mutually exclusive. Use `-Target` for physical devices or when emulator names are
duplicated.

Check the local SDK, commands, connected targets and optional project artifacts:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd doctor -ProjectRoot .
```

## Touch

Tap:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd tap `
  -Target 127.0.0.1:5555 -X 600 -Y 900
```

Smooth touch movement:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd swipe `
  -Target 127.0.0.1:5555 `
  -StartX 600 -StartY 1000 -EndX 600 -EndY 300 -DurationMs 500
```

Coordinates are physical pixels from the top-left of the target display, matching the official `uinput` contract.

Use `-DryRun` to validate and inspect the generated command without injecting input.

## Screenshot

Capture immediately:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd screenshot `
  -Target 127.0.0.1:5555 `
  -OutputPath ./tools/harmony-agent-tools/artifacts/current.jpeg
```

Capture after a relative delay:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd screenshot `
  -Target 127.0.0.1:5555 -DelayMs 250 `
  -OutputPath ./tools/harmony-agent-tools/artifacts/after-250ms.jpeg
```

`snapshot_display` is used with its portable JPEG output. Screenshot paths must end in `.jpg` or `.jpeg`; omitting
the extension appends `.jpeg`.

The JSON result contains an absolute `path`. Agents should read that field and return or inspect the image with the
host application's image facility. A shell script cannot itself emit a Codex `ImageContent` block; direct binary
image return should be added later through an MCP server or Codex plugin built on top of this module.

## Gesture frame capture

This command starts `uinput` asynchronously, schedules `snapshot_display` commands from a monotonic clock, then
pulls every image after capture:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd gesture-capture `
  -Target 127.0.0.1:5555 `
  -StartX 600 -StartY 1000 -EndX 600 -EndY 300 `
  -DurationMs 500 -CaptureAtMs 0,100,250,500 `
  -OutputDirectory ./tools/harmony-agent-tools/artifacts/gesture `
  -Prefix swipe-up
```

Each returned artifact reports:

- requested time;
- actual snapshot command start time;
- scheduling lateness;
- absolute local path.

This makes timing drift visible instead of pretending frame capture is exact.

## Self-test

The smoke test exercises portable command paths in dry-run mode, package discovery, scenario validation, CSV
time-point parsing and screenshot extension validation without requiring a device:

```powershell
./tools/harmony-agent-tools/tests/Smoke.ps1
```

## Scenarios

Scenarios combine tap, swipe, relative wait, screenshot and gesture capture:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd scenario `
  -ScenarioPath ./tools/harmony-agent-tools/examples/tap-and-capture.json `
  -Target 127.0.0.1:5555
```

Validate without touching a device:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd scenario `
  -ScenarioPath ./tools/harmony-agent-tools/examples/gesture-frames.json `
  -ValidateOnly
```

`atMs` schedules a step relative to scenario start. A `wait` step waits relative to the preceding step.

## Build, install and launch

Build:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd build `
  -ProjectRoot . -Product default -BuildMode debug
```

List build products before choosing what to install:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd packages -ProjectRoot .
```

Device-test HAPs are excluded by default. Pass `-IncludeTests` when they are needed.

Install without uninstalling:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd install `
  -Target 127.0.0.1:5555 `
  -PackagePath ./entry/build/default/outputs/default/entry-default-signed.hap
```

Normal launch:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd start `
  -Target 127.0.0.1:5555 `
  -Bundle com.example.music -Ability EntryAbility
```

Debug-mode launch:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd start `
  -Target 127.0.0.1:5555 `
  -Bundle com.example.music -Ability EntryAbility -DebugLaunch
```

`-DebugLaunch` maps to the documented `aa start -D` flag. Debug mode requires a debuggable application and
developer-mode target.

For 2-in-1 window checks, `start` also accepts `-WindowLeft`, `-WindowTop`, `-WindowWidth` and `-WindowHeight`.

Stop an application after debug-mode or isolated launch testing:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd stop `
  -Target 127.0.0.1:5555 -Bundle com.example.music
```

Read a bounded application log snapshot:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd logs `
  -Target 127.0.0.1:5555 -Bundle com.example.music -Level E -Tail 200
```

`logs` uses `devecocli log` and is bounded by default. It also accepts `-Keyword`, `-From` and `-To`; it intentionally
does not expose an unbounded follow mode.

Build, install and launch in sequence:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd deploy `
  -ProjectRoot . `
  -PackagePath ./entry/build/default/outputs/default/entry-default-signed.hap `
  -Target 127.0.0.1:5555 `
  -Bundle com.example.music -Ability EntryAbility -DebugLaunch
```

`deploy` stops after the first failed command. It never uninstalls the existing application.

## Portability boundary

> TODO(independent-repository): Extract this directory into a standalone `harmony-agent-tools` Git repository once
> the CLI and image-return interface stabilize, then consume it from application repositories through a pinned,
> reviewable version.

Portable core:

- `HdcAgentTools.psm1`
- `hdc-agent.ps1`
- `hdc-agent.cmd`
- `AGENTS.md`
- `scenario.schema.json`
- generic examples

Still needed before publishing as an independent project:

- choose a license and versioning policy;
- add CI on Windows PowerShell 5.1 and PowerShell 7;
- add mocked process tests plus opt-in device integration tests;
- define support across HDC/OS versions;
- package the module or publish a signed release artifact;
- optionally add an MCP server that converts JSON image artifacts into direct image responses.
