# Entry Module Instructions

These rules apply to the HarmonyOS `entry` module in addition to the repository root instructions.

## Before editing

- Read `../docs/agents/ARCHITECTURE.md` for ownership and dependency direction.
- Read `../docs/agents/QUALITY_GATES.md` and `../docs/agents/TEST_MATRIX.md`.
- Read the nearest more-specific `AGENTS.md` under `src`.

## ArkTS and HarmonyOS

- Use only APIs supported by the configured compatible and target SDK versions.
- Search unfamiliar HarmonyOS APIs with `devecocli docs search` and read the returned official document.
- Do not invent decorators, lifecycle callbacks, permissions, imports or manifest fields.
- Preserve strict-mode compatibility and case-sensitive normalized OHM URLs.
- Keep native and media resources paired with deterministic release paths.

## Module boundaries

- Keep application composition at the root lifecycle/shell boundary.
- Do not introduce a second application singleton, database or playback engine.
- Keep testable decisions out of large Builders and native callback bodies.
- Keep UI state observable and domain state owned by the relevant Store or coordinator.

## Validation

ArkTS, resource and configuration changes require relevant tests and `devecocli build`. Device-dependent behavior
must be reported separately from compilation.

