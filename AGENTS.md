# HarmonyOS Local Music Player Instructions

## Project

This repository contains a native HarmonyOS local music player.

- Language: ArkTS
- UI: ArkUI
- Application model: Stage
- Primary module: entry
- Playback engine: Media Kit AVPlayer
- Metadata: AVMetadataExtractor
- Background playback: AVSession Kit and Background Tasks Kit
- Database: ArkData relational store
- Settings: Preferences

## Product scope

The first version is an import-based local music player.

Users explicitly select audio files through the system Picker. Do not implement unrestricted full-storage scanning unless the task explicitly requires it and the configured SDK supports the required APIs.

The application should normally retain access to the original file through persisted URI authorization. Do not copy music files into the application sandbox unless the task explicitly requires managed imports.

## Architecture rules

Keep the following responsibilities separated:

- MediaImporter: file selection, URI authorization, deduplication and import.
- MetadataReader: metadata and artwork extraction.
- PlaybackEngine: AVPlayer lifecycle and state machine.
- PlaybackSession: AVSession and background playback.
- MusicRepository: tracks, albums, artists and playlists.
- SettingsRepository: small user preferences.
- PlayerStore: observable UI state.
- Pages and components: rendering and user interaction only.

UI components must not create or directly own AVPlayer instances.

Use one application-level PlaybackEngine instance.

## HarmonyOS API rules

Before using an unfamiliar API, run an official documentation search with DevEco CLI.

Examples:

- AVPlayer state transitions
- AVMetadataExtractor
- AudioViewPicker or DocumentViewPicker
- Picker URI permission persistence
- AVSession
- background audio long-running tasks
- relationalStore
- Preferences

Do not invent HarmonyOS APIs, decorators, permissions, imports, lifecycle callbacks or module.json5 fields.

Do not substitute Android MediaStore, Android Service, browser File APIs, Node.js fs APIs or React APIs for HarmonyOS capabilities.

Respect the compatibleSdkVersion and targetSdkVersion already configured by the project.

## File access rules

Picker URI access must be treated as an authorization-managed resource.

- Do not assume that saving a URI string provides permanent access.
- Persist authorization when supported and required.
- Handle revoked authorization.
- Handle moved or deleted files.
- Never request broad storage access when Picker is sufficient.
- Do not parse URI strings to infer physical paths.
- Close file descriptors and media resources correctly.

## Playback rules

PlaybackEngine must expose a stable application-level state independent of the raw AVPlayer state names.

Required application states:

- idle
- loading
- ready
- playing
- paused
- completed
- error

Handle rapid source switching and asynchronous state changes.

Do not call playback operations before AVPlayer reaches the required state.

Release or reset resources when they are no longer needed.

Do not destroy the global playback engine when a page is removed from the navigation stack.

## Background playback rules

Background audio requires both AVSession integration and the appropriate background task.

Keep AVSession metadata, playback state and position synchronized with PlaybackEngine.

Respond to system media controls.

Start the long-running task only when required and stop it when playback is stopped or no longer eligible for background execution.

Do not add unrelated permissions.

## Metadata rules

Use AVMetadataExtractor for documented metadata and artwork capabilities.

Provide fallbacks for missing title, artist, album and artwork.

Do not assume embedded lyrics are exposed by AVMetadataExtractor.

The initial lyric implementation should prefer sidecar LRC files.

Cache resized artwork in application storage. Do not store full artwork images as relational database BLOBs.

## Database rules

Use relational storage for tracks, playlists and playlist membership.

Every schema change must include a database version and migration.

Do not delete the user's media library when a migration fails.

Track records must retain enough information to detect duplicate imports and unavailable files.

## Validation

After modifying ArkTS, resources or configuration:

1. Run the available static checks.
2. Run:

   devecocli build

3. Fix all introduced build errors.
4. When a device or emulator is available, run the application.
5. Inspect logs for runtime failures.
6. Report which audio formats and scenarios were manually tested.

## Audio test matrix

At minimum, consider:

- AAC in M4A
- ALAC in M4A
- MP3
- FLAC
- WAV
- missing metadata
- embedded artwork
- large artwork
- Unicode filenames and tags
- corrupted files
- moved or deleted files

Do not claim a format works unless it was tested on the selected target device or emulator.

## Git rules

Inspect git status before editing.

Do not discard unrelated user changes.

Make focused changes.

Do not commit, push, change signing configuration, change the bundle name or update the SDK version unless explicitly requested.

At completion, provide:

- changed files;
- implementation summary;
- build result;
- test result;
- known limitations.
