# Page Instructions

Before changing pages, read:

- `../../../../../docs/agents/UI_CONTRACTS.md`
- `../../../../../docs/agents/ARCHITECTURE.md`
- `../../../../../docs/agents/CHANGE_WORKFLOW.md`
- `../../../../../docs/agents/QUALITY_GATES.md`
- `../../../../../docs/agents/TEST_MATRIX.md`

- Pages render Store state, compose feature components and dispatch user intent.
- Feature pages must not create private nested Navigation stacks.
- Do not recreate shared titles, back buttons, scrolling blur or persistent chrome.
- Do not access AVPlayer, PlaybackSession, SQL, Preferences or raw file operations.
- Do not create long-lived repositories or application runtimes.
- Keep page-local state limited to presentation concerns.
- Shared behavior belongs in a policy, Store, navigation controller or domain owner.
- Lists, Grids and Scrolls use the shared edge-to-edge page behavior.
- Verify back behavior, persistent chrome and responsive promotion/demotion when navigation changes.
