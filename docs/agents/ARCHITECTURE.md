# Architecture Boundaries

## Purpose

This document defines ownership and dependency direction. It describes the current application boundary while also
preventing new coupling. If implementation and this document disagree, determine whether the code is an intentional
exception or architecture drift before changing either.

## Application composition

The current application is composed through these boundaries:

- `entryability/EntryAbility.ets` owns HarmonyOS ability and window lifecycle.
- `pages/Index.ets` is the root ArkUI shell and the current UI composition boundary.
- `playback/PlaybackRuntime.ets` is the singleton playback command facade. It owns the single PlaybackEngine,
  PlaybackSession, PlaybackQueue and PlayerStore and commits queue/Store projections atomically.
- Playback coordinators delegate persistence and restore planning, track media work, PiP lifecycle synchronization
  and audio recovery decisions. They do not create another engine, session, queue, Store or repository.
- PlaybackRuntime exposes the shared MusicRepository used by the root shell to construct LibraryStore and
  PlaylistStore.
- SettingsRepository owns persisted preferences; AppSettingsStore exposes observable settings state.

Leaf pages and components must not create an alternative application graph.

## Dependency direction

Use this direction:

```text
EntryAbility
  └─ root composition and application lifecycle
       ├─ observable stores
       ├─ application command facades
       └─ repositories
            └─ databases, Picker access, metadata and native services

Pages and components
  ├─ read observable stores
  ├─ render state
  └─ issue user-intent commands
```

Lower-level data, playback and service code must not depend on pages or UI components.

## UI boundary

Pages and components may:

- read observable Store state;
- invoke commands exposed by the current application coordinator;
- own ephemeral presentation state such as menu visibility, local gesture progress and focus;
- call pure layout, formatting and interaction policies.

Pages and components must not:

- instantiate AVPlayer, PlaybackEngine, PlaybackSession, relationalStore or a file Picker authorization service;
- perform SQL, metadata extraction or raw file access;
- maintain a second copy of playback, library or settings truth;
- construct long-lived repositories or application runtimes;
- work around a shared invariant with page-specific state.

`playbackRuntime` is currently the playback command facade. Leaf UI may invoke its public playback commands, but
must not access its internal engine, session or repository. The root `Index` composition boundary is the only current
UI exception allowed to share `playbackRuntime.repository` with application stores.

Prefer introducing a narrow command interface when new behavior would make leaf UI depend on more PlaybackRuntime
internals. Do not perform a repository-wide dependency-injection rewrite solely to rename the existing facade.

## Playback ownership

- PlaybackEngine exclusively owns AVPlayer creation, raw state transitions and source preparation.
- PlaybackRuntime coordinates commands, queue behavior, engine/session integration and atomic Store projection.
- PlaybackPersistenceCoordinator owns restore planning, an ordered latest-wins pump for relational queue snapshots
  and cursor writes, and playback preference writes. It uses the Runtime-owned queue-build epoch for stale-result
  checks and never projects queue state itself. A persisted snapshot atomically records stable base positions, the
  active playback permutation, cursor and shuffle mode so duplicate tracks and natural-order restoration survive
  restart.
- PlaybackMediaCoordinator owns the single track request epoch and playback-time lyrics/artwork/palette work.
- PlaybackPictureInPictureCoordinator delegates snapshots and lifecycle to the existing
  PlaybackPictureInPicture implementation.
- PlaybackAudioRecoveryCoordinator owns focus/output recovery intent and consumes each automatic resume once.
- PlaybackSession owns AVSession and background-control integration.
- PlaybackPictureInPicture owns system PiP nodes, lifecycle callbacks and control-event adaptation.
- PlayerStore is observable UI state, not a command service and not an AVPlayer state machine.
- PlayerStore owns the ArkUI queue-projection notification policy and exposes active playback order: identical
  snapshots are a no-op, pure permutations atomically replace the order behind stable position slots without any
  LazyForEach data operation, cursor changes update only affected slots, and structural changes use one reload.
  Queue entry identity is resolved inside each instantiated slot leaf so order revisions do not dirty the page root.
  Navigation containers do not receive PlayerStore; leaf playback surfaces reference the application PlayerStore
  directly and own the deep observation boundary.
- PlaybackQueue owns stable base-entry identity, the active playback permutation, shuffle and exact-entry cursor
  invariants. The UI projects playback order while persistence records both base and playback positions. Insert,
  append and removal operations update both orders without collapsing shuffled order into the natural base order.
- A queue-page shuffle refresh is a coordinated presentation and persistence transaction. The page first unmounts
  the queue projection, waits for an ArkUI frame acknowledgement, then asks PlaybackRuntime to change the
  PlaybackQueue permutation and submit an immutable snapshot through PlaybackPersistenceCoordinator's exact-write
  receipt. Ordinary queue persistence remains latest-wins; the exact receipt is an ordered barrier and is not
  implemented by flushing or observing an ordinary coalesced write.
- Support policies own independently testable decisions such as power, reconnect and state reduction.

Use request epochs or equivalent invalidation for asynchronous work that can be superseded. A stale completion must
not publish state, release a resource now owned by newer work, or clear a current operation.

## Library ownership

- MediaPickerService owns Picker interaction and documented URI authorization.
- MediaImporter is the stable library-facing façade and owns the single active MediaImportOperation.
- MediaImportSession owns one Picker import session and its per-item outcomes; MediaFileChecker owns file-check
  orchestration; MediaDuplicateProof owns full-fingerprint duplicate proof; MediaArtworkPipeline owns bounded
  artwork work and importer-scoped cleanup.
- LibraryRemovalService coordinates committed library deletion with post-commit Picker authorization cleanup.
- MusicFileShareCoordinator owns music-file share validation and orchestration through narrow track-source,
  Picker-URI-access and system-share-presenter ports. Index owns the coordinator and supplies the current ability
  context; adapters never copy the audio file, derive a physical path or retain the context.
- MetadataReader owns documented media metadata and artwork extraction.
- `libwplayermedia.so` implements the MP3/FLAC fallback parser and bounded pixel conversion behind
  MediaFileTasks. It synchronously borrows caller-owned file descriptors on taskpool workers, uses positioned reads
  and never closes or retains those descriptors. NativeMediaMetadataAdapter keeps tag normalization in the library
  domain; pages and other callers do not import the native module directly.
- MusicRepository is the library facade used by stores and playback coordination.
- LibraryDatabase owns schema creation, versioning and relational-store lifecycle.
- MusicLibraryQueries is the stable repository-facing query facade. Track, album, detail/navigation and maintenance
  data-access classes own their same-domain reads and writes; MusicRepository retains projection invalidation.
- MusicLibraryImporter owns transactional import persistence.
- LibraryStore owns observable library UI state and session-only operation reports.
- Detail stores expose bounded previews. Full artist-track, artist-album and related-album collections use
  route-owned collection state backed by independently paged data sources; detail pages do not retain or preload
  those complete result sets.
- ArtworkCache owns persistent resized artwork files; ArtworkMemoryCache owns playback-time decoded artwork.

Do not make URI strings, display names, quick fingerprints or metadata alone authoritative proof of physical file
identity.

## Playlist ownership

- PlaylistRepository owns playlist and membership persistence.
- PlaylistStore owns observable playlist UI state.
- M3uCodec and M3uEncoding own parsing, serialization and encoding decisions.
- M3uImportMatcher owns matching imported rows against the current library.
- M3uTransferService owns Picker/file orchestration for transfer operations.
- UI policies own selection and menu decisions, not persistence.

PlaylistRepository shares LibraryDatabase through MusicRepository. Do not create a second relational store for the
same library graph.

## Settings ownership

- SettingsRepository owns Preferences reads and writes.
- AppSettingsStore owns observable settings state.
- Small normalization and fallback decisions belong in named policy types.
- Pages render and dispatch settings changes; they do not read Preferences directly.
- PlayerPageKeepScreenOnController owns the effective window keep-screen-on state from bound-window, foreground,
  player-page visibility and user-preference inputs. EntryAbility owns its Window binding; UI submits visibility and
  preference intent without calling Window APIs directly.

## Navigation ownership

- Persistent navigation hosts live at the root tab shell.
- Do not attach implicit palette animations to an entire HdsNavigation or HdsNavDestination. Palette transitions
  are driven explicitly by the appearance owner so unrelated playback state cannot animate or rebuild a complete
  navigation render tree.
- Each tab owns one controlled navigation stack.
- Shared route definitions and responsive promotion/demotion logic stay in the navigation layer.
- `IndexNavigationController` and the root shell composition own route selection, tab controllers and the persistent
  `NavPathStack` and `Scroller` identities. `ResponsiveNavigationShell` owns breakpoint-specific rendering and its
  root selection-controller identities.
- `ResponsiveNavigationRouteContent` builds root pages and navigation destinations from navigation-layer-owned
  identities and user-intent callbacks; it does not own responsive state or create another navigation stack.
- Collection destinations own their paging, selection and scroll identities in their route parameters so compact
  and expanded hosts render the same durable state without nesting another Navigation.
- `ResponsiveNavigationModalHost` hosts navigation-level sheets and content covers while visibility and import
  orchestration remain Shell-owned. `SelectionNavigationTitleBar` presents selection chrome without owning
  selection actions or state.
- Feature pages must not create private nested Navigation stacks.
- Detail pages do not replace or own persistent tab/player chrome.

Detailed behavior is defined in `UI_CONTRACTS.md`.

## Boundary-change checklist

When changing an ownership boundary:

1. Name the invariant and its new owner.
2. Search all direct imports and construction sites.
3. Update callers in one coherent change.
4. Remove the superseded path; do not leave two active owners.
5. Add tests at the policy or state boundary.
6. Update this document and affected scoped agent-instruction files.
