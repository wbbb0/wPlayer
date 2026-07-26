# Settings Domain Instructions

Before changing settings behavior, read:

- `../../../../../docs/agents/ARCHITECTURE.md`
- `../../../../../docs/agents/CHANGE_WORKFLOW.md`
- `../../../../../docs/agents/QUALITY_GATES.md`
- `../../../../../docs/agents/TEST_MATRIX.md`

- SettingsRepository exclusively owns Preferences access.
- AppSettingsStore owns observable settings state.
- Pages and components must not access Preferences directly.
- Put normalization, fallback and compatibility decisions in named policies.
- Handle missing and corrupt stored values deterministically.
- Keep preferences small; relational entities and operation reports do not belong in Preferences.
- Run relevant settings/policy tests and the normal build.

