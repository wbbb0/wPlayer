# Harmony Agent Tools Instructions

## Scope

This directory is a portable agent-facing toolkit for HarmonyOS development and device automation. Keep it
independent from the containing application's source code, bundle name, signing identity and build layout.

The public entry point is `hdc-agent.cmd` on Windows and `hdc-agent.ps1` when direct PowerShell execution is
available. `HdcAgentTools.psm1` contains reusable implementation functions.

## Interface contract

- Successful commands write one JSON value to stdout.
- Diagnostics and failures go to stderr and return a non-zero exit code.
- Image-producing commands return absolute local artifact paths.
- Device-changing commands require explicit target selection when multiple usable targets are connected.
- DevEco emulator operations should prefer exact `-EmulatorName` selection so callers do not persist dynamic ports.
- Dry-run mode must not require a connected target or mutate device/project state.
- Do not add an unbounded log-follow mode to the default CLI.

## Safety

- Never choose arbitrarily between multiple devices.
- Never uninstall an application automatically. Uninstalling may delete user data and requires explicit approval.
- Never modify signing configuration, SDK versions, bundle names or application source.
- Keep generated screenshots and other runtime artifacts under the ignored `artifacts/` directory.
- Clean up exact temporary device files after capture; never use broad remote deletion patterns.

## Portability

- Maintain Windows PowerShell 5.1 compatibility until the supported-runtime policy changes explicitly.
- Prefer official `hdc`, `devecocli` and HarmonyOS shell commands.
- Keep project-specific values in CLI arguments, scenario files or examples, never in the module.
- Isolate Windows-only discovery such as DevEco emulator process mapping and return a clear unsupported-platform
  error elsewhere.

## Change workflow

When adding or changing a command:

1. Update `README.md` and the CLI `ValidateSet`.
2. Keep argument validation at the CLI/module boundary.
3. Add a no-device dry-run assertion to `tests/Smoke.ps1` when possible.
4. Run `tests/Smoke.ps1`, parse all PowerShell and JSON files, and run `git diff --check`.
5. For device operations, perform an opt-in integration check on one explicitly identified target and report it.
