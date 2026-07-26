# Harmony Agent Tools

`harmony-agent-tools` is a self-contained PowerShell 5.1-compatible wrapper around official HarmonyOS command-line
tools. It is designed for coding agents and intentionally avoids importing application source or build
configuration so the directory can later become a standalone repository.

## Goals

- make device selection explicit and safe when several targets are connected;
- map running DevEco emulator names to their HDC targets;
- provide simple pixel or normalized touch, wait and screenshot commands;
- capture animation frames at specific offsets while a gesture is still running;
- return machine-readable JSON with absolute image paths, plus direct MCP image content;
- crop, compare and assert screenshots without application-specific test code;
- wrap build, install, normal launch and debug launch without automatically uninstalling applications;
- wrap local ArkTS tests and on-device ohosTest execution;
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

Query the physical target display:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd display -EmulatorName "Pura 90"
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

For reusable scenarios, use coordinates normalized to the range `0..1`:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd tap `
  -EmulatorName "Pura 90" -XRatio 0.5 -YRatio 0.8

./tools/harmony-agent-tools/hdc-agent.cmd swipe `
  -EmulatorName "Pura 90" `
  -StartXRatio 0.5 -StartYRatio 0.8 -EndXRatio 0.5 -EndYRatio 0.2
```

The command queries the target dimensions and converts ratios to physical pixels. For device-free dry runs, pass
`-DisplayWidth` and `-DisplayHeight` explicitly.

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

The JSON result contains an absolute `path`. The included MCP adapter converts that file into direct image content.

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

The MCP adapter has a device-free content test:

```powershell
npm run test:mcp
```

Run the complete portable verification suite with one command:

```powershell
./tools/harmony-agent-tools/tests/Verify.ps1
```

Add `-EmulatorName "Pura 90"` to include direct MCP screenshot and normalized-touch integration.

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
Scenarios may use pixel fields or normalized fields such as `xRatio`, `startXRatio` and `endYRatio`. When normalized
scenarios are dry-run, declare `displayWidth` and `displayHeight` in the scenario.

## Image inspection and visual assertions

Inspect and crop an image:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd image-info -ImagePath ./actual.jpeg

./tools/harmony-agent-tools/hdc-agent.cmd crop-image `
  -ImagePath ./actual.jpeg -OutputPath ./crop.png `
  -CropX 100 -CropY 200 -CropWidth 600 -CropHeight 400
```

Compare screenshots and emit a red-highlighted difference image:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd compare-images `
  -BaselinePath ./baseline.png -ActualPath ./actual.png `
  -DifferencePath ./difference.png `
  -PixelTolerance 8 -MaxDifferenceRatio 0.01 -MaxMeanError 0.005
```

`assert-image` accepts the same thresholds and exits non-zero when they are exceeded. Images must have matching
dimensions; crop responsive regions first when the full display size is expected to differ.

## Tests

Run ArkTS local tests through Hvigor:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd test-local -ProjectRoot . -Module entry
```

Build, install and execute the `ohosTest` package:

```powershell
./tools/harmony-agent-tools/hdc-agent.cmd test-device `
  -ProjectRoot . -EmulatorName "Pura 90" `
  -Bundle com.example.music -Module entry -TestModule entry_test
```

`test-device` installs with replacement and never uninstalls. Use `-SkipBuild` to run existing signed HAPs, or pass
`-MainPackagePath` and `-TestPackagePath` when artifact names differ from the standard layout.

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

## Codex plugin and MCP image return

The directory is also a valid Codex plugin. Its MCP server exposes:

- `harmony_display`;
- `harmony_screenshot`;
- `harmony_tap`;
- `harmony_swipe`;
- `harmony_gesture_capture`;
- `harmony_compare_images`.

Touch tools accept physical or normalized coordinates and can return the post-action screenshot in the same tool
response. Install Node dependencies once with `npm install`; validate the adapter with:

```powershell
npm run check
npm run test:mcp
npm run test:mcp:device -- "Pura 90"
```

The repository does not modify a personal Codex marketplace or globally install the plugin. That remains an
explicit consumer choice when this directory is extracted or distributed.

## Portability boundary

> TODO(independent-repository): Extract this directory into a standalone `harmony-agent-tools` Git repository once
> the CLI and image-return interface stabilize, then consume it from application repositories through a pinned,
> reviewable version.

Portable core:

- `HdcAgentTools.psm1`
- `ImageAgentTools.psm1`
- `TestAgentTools.psm1`
- `hdc-agent.ps1`
- `hdc-agent.cmd`
- `.codex-plugin/plugin.json`, `.mcp.json` and `mcp/`
- `AGENTS.md`
- `scenario.schema.json`
- generic examples

Still needed before publishing as an independent project:

- choose a license and versioning policy;
- add CI on Windows PowerShell 5.1 and PowerShell 7;
- add fully mocked process tests in addition to the current smoke and opt-in device integration checks;
- define support across HDC/OS versions;
- package the module or publish a signed release artifact;
- decide whether the standalone distribution ships as a Codex plugin, PowerShell module, npm package, or all three.
