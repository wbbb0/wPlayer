# Component Instructions

Before changing shared components, read:

- `../../../../../docs/agents/UI_CONTRACTS.md`
- `../../../../../docs/agents/ARCHITECTURE.md`
- `../../../../../docs/agents/CHANGE_WORKFLOW.md`
- `../../../../../docs/agents/QUALITY_GATES.md`
- `../../../../../docs/agents/TEST_MATRIX.md`

- Components render observable state and emit user intent.
- Do not instantiate AVPlayer, PlaybackEngine, PlaybackSession, repositories, relational stores or Preferences.
- Prefer shared HDS chrome, layout specifications, policies and system Symbols.
- Keep changing observable values read directly inside framework-owned Builders.
- Keep gesture policy separate from animation side effects when practical.
- Preserve gesture arbitration, clipping, pressed feedback and system material behavior.
- Put reusable geometry and motion constants in named specification types.
- Invalidate stale asynchronous rendering and animation completions.
- Verify every responsive host and adjacent interaction affected by a shared component change.
