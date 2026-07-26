# Device Test Instructions

Before changing device tests, read:

- `../../../docs/agents/TEST_MATRIX.md`
- `../../../docs/agents/QUALITY_GATES.md`

- Import and invoke every new suite from `ets/test/List.test.ets`.
- Use device tests for behavior requiring HarmonyOS services, permissions, media resources or lifecycle.
- Make setup and cleanup explicit and safe for repeated runs.
- Do not uninstall the application or erase user data without approval.
- Record the target device/emulator and relevant OS/API version.
- Distinguish automated device coverage from manual interaction checks.
- Do not claim unexecuted formats, background behavior or system controls passed.
