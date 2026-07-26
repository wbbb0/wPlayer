# Playlist Domain Instructions

Before changing playlist behavior, read:

- `../../../../../docs/agents/ARCHITECTURE.md`
- `../../../../../docs/agents/CHANGE_WORKFLOW.md`
- `../../../../../docs/agents/QUALITY_GATES.md`
- `../../../../../docs/agents/TEST_MATRIX.md`

- PlaylistRepository owns playlist and membership persistence.
- PlaylistStore owns observable playlist state and operation status.
- M3U parsing, encoding, matching and file orchestration remain separate responsibilities.
- Preserve input order and stable identity where the operation contract requires it.
- Treat malformed rows, ambiguous matches, Unicode and multiple encodings as normal input cases.
- Do not let UI components perform SQL or file transfer.
- Keep the protected completed-history behavior in shared policy rather than menu/page exceptions.
- Run playlist and M3U tests plus repository-adjacent tests and the normal build.
