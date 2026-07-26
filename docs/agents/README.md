# Agent Documentation

This directory contains the detailed engineering rules routed by the repository
[AGENTS.md](../../AGENTS.md).

| Document | Authority |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Ownership, composition and dependency direction |
| [CHANGE_WORKFLOW.md](CHANGE_WORKFLOW.md) | Investigation, implementation and completion workflow |
| [QUALITY_GATES.md](QUALITY_GATES.md) | Executable validation and future script contract |
| [TEST_MATRIX.md](TEST_MATRIX.md) | Regression routing, device/UI checks and claim discipline |
| [UI_CONTRACTS.md](UI_CONTRACTS.md) | Responsive navigation, HDS surfaces, gestures and morph behavior |

Keep this directory agent-focused:

- Human environment setup belongs in `../BUILDING.md`.
- Release identity and signing operations belong in `../RELEASING.md`.
- Directory-specific invariants belong in the nearest scoped agent-instruction file.
- Do not duplicate a rule across documents; link to its authoritative location.
