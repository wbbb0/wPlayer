# Local Test Instructions

Before changing local tests, read:

- `../../../docs/agents/TEST_MATRIX.md`
- `../../../docs/agents/QUALITY_GATES.md`

- Import and invoke every new suite from `List.test.ets`.
- Add regression coverage for defect fixes when host-runnable policy or state can express the invariant.
- Keep tests deterministic and independent of order.
- Test public behavior and invariants rather than duplicating implementation.
- Include boundary, empty, error, cancellation and stale-completion cases where applicable.
- Prefer focused fixtures and named builders over repeated opaque literals.
- Do not claim device/framework behavior from local policy tests.
