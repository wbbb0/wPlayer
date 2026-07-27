# Library Domain Instructions

Before changing library behavior, read:

- `../../../../../docs/agents/ARCHITECTURE.md`
- `../../../../../docs/agents/CHANGE_WORKFLOW.md`
- `../../../../../docs/agents/QUALITY_GATES.md`
- `../../../../../docs/agents/TEST_MATRIX.md`

## Ownership

- Picker interaction and URI authorization belong to MediaPickerService.
- Import orchestration, deduplication and per-item outcomes belong to MediaImporter.
- Committed library deletion and post-commit URI authorization cleanup belong to LibraryRemovalService.
- Metadata and embedded artwork extraction belong to MetadataReader and format-specific readers.
- Relational lifecycle and schema belong to LibraryDatabase.
- Queries and writes belong to their repository/data helpers.
- Observable library state and session-only reports belong to LibraryStore.
- Persistent resized artwork belongs to ArtworkCache.

## File access

- Treat Picker access as revocable authorization.
- Do not derive physical paths from URI strings.
- Do not assume saving a URI preserves access.
- Close descriptors, extractors and temporary resources on every terminal path.
- Handle missing, moved, corrupt and no-longer-authorized files.
- Use full fingerprints only when required for duplicate proof; quick fingerprints are candidate filters.

## Persistence

- Increment the database version for every schema change.
- Do not persist operation progress, reports or per-item outcomes.
- Do not store full artwork in relational BLOBs.
- Preserve repository invalidation for every affected projection.
- When production data preservation is required, use incremental migration without destructive fallback.

## Verification

Run focused importer, repository, metadata or artwork tests plus adjacent suites and the normal build. Use only
actually tested formats when reporting compatibility.
