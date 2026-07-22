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

## UI and interaction requirements

On compact layouts, the primary navigation uses a floating horizontal HDS tab bar with four pages: playlists,
songs, albums and more. On large and unfolded layouts, use a separate vertical HDS tab instance, omit the more tab
and page, expose the destinations from more directly as tabs and present them as root pages without back buttons.

- Prefer system Symbols when an appropriate icon exists. Use proper SVG resources for custom icons; do not use text characters as icons.
- Keep the navigation and mini player as separate rounded glass surfaces.
- On compact layouts, expanding one surface collapses the other to its current-page icon or album artwork.
- On large and unfolded layouts, follow the HDS responsive behavior and allow the full navigation and mini player to remain visible on opposite sides.
- Preserve system material effects, pressed highlights, depth changes and smooth size transitions. Do not replace system glass with a flat translucent color.
- Use edge-to-edge immersive layout with transparent system bars. Backgrounds may extend under system UI, but interactive content must dynamically respect status bar, navigation indicator and cutout avoid areas.

The mini player interaction contract is:

- Horizontal dragging moves only the track text. Album artwork and playback controls remain fixed.
- Clip mini-player content to its rounded parent so translated content never escapes the surface.
- A horizontal action threshold may provide light haptic feedback, but must not trigger track changes until playback behavior is implemented.
- Upward dragging expands the player interactively and follows the finger. Releasing below the threshold returns without overshoot; releasing above it completes the expansion.
- Tapping the expanded mini-player artwork or track text opens the full player. Playback controls keep their own click behavior.
- Gesture arbitration must preserve taps, horizontal dragging and vertical dragging together. Do not fix one gesture by suppressing the others.

The full-player transition is a shared-element morph:

- Freeze both source and destination geometry when a transition starts.
- Use one overlay artwork instance and one progress value for position, scale, corner radius and shadow.
- Keep the final full-player canvas at its final layout size; animate the clipping shell rather than relaying out the full content tree every frame.
- Opening must respond immediately. The overlay replaces the source surface without a fade-in.
- When closing or cancelling, finish the geometry animation first, then fade only the replacement background to reveal the real HDS glass. Remove the replacement foreground and reveal the real controls in the same final frame.
- Preserve the pre-transition HDS mini-bar state when returning from the full player.

## UI implementation rules

- Use the HDS component family for project-level navigation chrome and material surfaces. Titles, back buttons,
  scrolling blur and secondary destinations must come from shared HDS navigation templates; do not recreate them
  independently inside individual pages.
- Keep navigation hosts at the persistent-tab shell boundary, with one controlled stack per tab and a shared route
  registry. Feature pages must not create private nested Navigation stacks.
- Use separate HdsTabs instances and controllers for compact and expanded navigation; an HdsTabsController must not
  control both instances. Keep each instance's TabContent collection structurally stable while it is active, and
  keep selection, route IDs, controlled stacks and durable page state outside the responsive hosts.
- Define destinations exposed by the compact more page and expanded side navigation in one shared registry. When
  crossing a responsive breakpoint, promote the active compact destination to an expanded root page or demote the
  expanded root back onto the more-tab stack so page identity and back behavior remain coherent.
- The expanded vertical HdsTabs owns its side frame and divider. Do not add wrapper margins, borders or replacement
  backgrounds around it; configure its built-in bar width and layout properties directly.
- Keep expanded side-tab content switching immediate: disable both swipe navigation and the HdsTabs page transition
  animation. Compact bottom-tab motion remains governed by its own HdsTabs instance.
- Size the expanded HdsTabs bar responsively: use a compact icon-over-label bar in portrait unfolded layouts and a
  wider icon-beside-label bar in landscape layouts. Keep portrait items centered; when landscape side-tab contents
  must share a leading edge, keep the custom tab builder inside HdsTabs and let HdsTabs continue to own the side
  frame and divider.
- Page backgrounds are edge-to-edge solid theme colors. Scrollable viewports should cover the physical page and
  use shared content start/end offsets to keep initial and final items readable behind floating chrome; do not
  shrink List or Grid viewports with per-page top or bottom padding.
- Apply the shared page scroll behavior to Scroll, List and Grid: content may pass beneath HDS title chrome,
  Spring edge effects are enabled, virtual caches retain items beneath overlays, and short Scroll content is
  top-aligned instead of vertically centered.
- Persistent bottom tabs and player controls remain above secondary destinations. Each tab owns one controlled
  navigation stack so detail pages preserve the selected tab and its floating chrome.
- Outside the theme accent and semantic status colors, use neutral grayscale tokens. Dark page backgrounds are
  AMOLED black; do not introduce blue-tinted neutral backgrounds, text or glass surfaces.
- Use system responsive Grid policies or a shared responsive layout specification. Do not hard-code a fixed column
  count in feature pages.
- Model multi-stage UI transitions with an explicit enum phase instead of combinations of loosely related booleans.
- Sequence animations with documented completion callbacks. Do not coordinate animation stages with unguarded `setTimeout` calls.
- Invalidate stale animation completions when a newer transition starts, so rapid repeated input cannot clear or overwrite current state.
- Keep motion and layout constants in a dedicated specification type instead of scattering magic numbers through Builders.
- Aggregate geometry as frame or point objects and isolate HDS geometry adaptation from rendering code.
- Values that must update reactively inside an ArkUI Builder should be read directly from observable state. Do not pass changing primitive values through Builder parameters that may be captured by framework-owned builders.
- Prefer render transforms such as translate and scale for interactive movement. Avoid relying on layout-position changes for frame-by-frame animation.
- Pages and UI components must not become playback state owners. When playback is implemented, bind them to PlayerStore.

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

Every schema change must increment the database version.

The application is currently in development. When the database version changes, it is acceptable to drop and
rebuild the local music-library database instead of implementing an incremental data-preserving migration. Treat
this as an explicit development-only workflow, and do not describe it as production-safe migration behavior.

If a task explicitly requires preserving existing user data or preparing a production release, replace the
destructive rebuild with a versioned incremental migration and ensure migration failures do not delete the user's
media library.

Import and sort-index progress and result reports are session-only state. Keep them in the application-level
observable store; do not persist reports or per-item outcomes in relational storage or Preferences. Dismissing the
report surface or navigating away must not interrupt the active operation, while terminating the application may
discard the report and its completed-item details.

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

For navigation and player UI changes, also verify when the relevant targets are available:

- compact and unfolded layouts;
- mini-player artwork and text taps;
- playback button taps;
- horizontal dragging in both directions and elastic return;
- upward drag completion and below-threshold cancellation;
- full-player close and background material handoff;
- rapid repeated open and close input;
- system-bar and bottom-indicator avoidance.

Prefer the local Pura X Max emulator for repeatable wide-fold validation when a physical device is unavailable.

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

Never commit signing passwords, private keys, certificate stores, provisioning profiles or machine-specific signing paths. Keep local `build-profile.json5` signing material out of commits even when other project changes are being published.

### Local signing workflow

- Use the tracked root `build-profile.json5` as the only signing configuration source so DevEco Studio can manage it.
  Local signing makes this tracked file intentionally dirty.
- The Git version of `build-profile.json5` must contain exactly one empty `app.signingConfigs: []`, product mappings
  `default → default` and `release → release`, and no signing passwords or machine-specific certificate, profile,
  and keystore paths.
- Do not use Git `assume-unchanged` or `skip-worktree` to hide signing changes. Hidden tracked changes are too easy to
  publish accidentally. `.gitignore` also does not suppress changes to an already tracked file.
- Enable the repository hook with `git config core.hooksPath .githooks`. Before every commit, run
  `./tools/check-signing-profile.ps1 -Staged`; CI runs the same policy against committed content.
- Preserve local signing configuration outside the repository only while preparing a commit, sanitize and commit the
  portable profile, then restore the local `build-profile.json5`. Never stage the restored local version.
- After changing the signing workflow, validate both paths: build the portable empty-signing profile, restore the
  local profile, build a signed HAP, install it with `hdc install -r`, launch the main ability, and inspect startup logs.

### Release signing material

The public AppGallery release uses a dedicated release key, release certificate, and release Profile. Do not reuse
the automatically generated debug key or debug Profile for a `release` build.

- On each authorized Windows development machine, ask the user to place the release files outside the repository
  under `C:\Users\<user>\.ohos\release`. For the current release identity, expect:
  - `wplayer-release.p12`: the private release KeyStore;
  - `wplayer-release.cer`: the AppGallery Connect release certificate created from the CSR;
  - `wplayer-releaseRelease.p7b`: the AppGallery Connect release Profile for
    `com.wabebabo.wplayer`;
  - `wplayer-release.csr`: the certificate request retained for records or certificate renewal; it is not a signing
    input after the `.cer` has been issued.
- Never ask the user to paste KeyStore or key passwords into chat, source files, shell history, logs, or tracked
  configuration. Have the user enter both passwords in DevEco Studio locally. Preserve the exact encrypted password
  strings generated by DevEco Studio; do not try to derive, decrypt, or replace them with plaintext.
- Use a dedicated signing configuration name such as `release`, the KeyStore alias chosen when the release key was
  generated (currently `wplayerRelease`), and `SHA256withECDSA`. Validate that the `.cer`, `.p7b`, bundle name, alias,
  and `.p12` belong to the same release identity before publishing.
- DevEco Studio writes the local release signing object directly into tracked `build-profile.json5`; this is expected
  for local builds but must never be committed. Before committing, restore the portable empty array while retaining
  the `default → default` and `release → release` product mappings.
- Keep debug and release signing material as separate local entries in `build-profile.json5`: product `default`
  selects `default`, and product `release` selects `release`. `assembleReleaseSignedApp` verifies the latter.
- Before a release build, confirm the local `release` product selects the dedicated `release` entry. Build with
  `buildMode=release` and verify the generated metadata reports `BUILD_MODE: release`, `debug: false`, and a signed
  `.app` output. Do not infer release readiness only from the output filename.
- Backing up the release `.p12`, its alias, both passwords, `.cer`, and `.p7b` is the user's responsibility. Advise
  at least two encrypted backups. Never copy release material to the repository, Codex memory, temporary artifacts,
  or a new machine without explicit user authorization.

### New-machine environment initialization

Use this checklist after cloning the repository onto a new Windows development machine:

1. Install a DevEco Studio version that provides the SDK required by `build-profile.json5`. Set
   `DEVECO_SDK_HOME` to the SDK parent directory, for example
   `C:\Program Files\Huawei\DevEco Studio\sdk`; do not point it at `sdk\default`, `hms`, or `openharmony`. Confirm the
   selected SDK contains the configured API level before changing any project SDK version.
2. Install the project CLI with `npm install -g @deveco/deveco-cli`, open a new terminal, and verify it with
   `devecocli --version`. If PowerShell selects `devecocli.ps1` and rejects it because of the execution policy, fix
   the local-script policy and open a new terminal, or invoke the generated `devecocli.cmd` shim. Do not weaken a
   managed machine policy from project automation.
   Before running the CLI, verify `$env:DEVECO_SDK_HOME` is non-empty and points to the SDK parent directory. An
   empty or invalid value causes Hvigor sync to fail with configuration error `00303217`; for the default DevEco
   installation, set it for the current shell with
   `$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'`.
   Allow enough command timeout for both Hvigor sync and compilation. Killing `devecocli build` after only a few
   seconds can surface a secondary Node.js `EPIPE` error because the CLI's output pipe was closed; that error does
   not identify the underlying project build result.
   Hvigor daemons may retain evaluated build-profile state. After changing local signing in `build-profile.json5`,
   stop the daemon with the DevEco-provided `hvigorw --stop-daemon`, then run the build again in a fresh process.
3. Run `git status` before making changes. If Git reports dubious ownership after copying the repository from a
   different Windows account, verify the directory is trusted and then add this exact repository path to Git's
   global `safe.directory` list. Never use a wildcard safe-directory exception.
4. Run `git config core.hooksPath .githooks`, then `./tools/check-signing-profile.ps1` and `devecocli build` against
   the cloned portable profile. This validates the signing guard, dependency installation, Hvigor sync, SDK discovery,
   ArkTS compilation, resources, and the unsigned build before local credentials are involved.
5. For ordinary device development, create or select the machine's debug signing configuration once. For AppGallery
   publishing, first have the user copy the dedicated files listed under `Release signing material` to
   `C:\Users\<user>\.ohos\release`, then configure those files as a separate release signing identity in DevEco
   Studio and have the user enter the two passwords locally. The IDE writes `app.signingConfigs` and the product-level
   `signingConfig` directly into `build-profile.json5`; keep that local file dirty and never stage it with signing
   material. Before a commit, back it up outside the repository, restore the portable empty-signing shape, run the
   staged signing guard, commit, and then restore the local file.
6. Run a normal `devecocli build` with the locally configured profile and confirm it produces
   `entry-default-signed.hap`. Before publishing source changes, run `./tools/check-signing-profile.ps1 -Staged` and
   inspect `git diff --cached -- build-profile.json5` to confirm no local signing material is staged.
7. Verify the target with `hdc list targets -v`, install with
   `hdc install -r entry/build/default/outputs/default/entry-default-signed.hap`, unlock the device, launch with
   `hdc shell aa start -a EntryAbility -b com.wabebabo.wplayer`, and inspect `hilog` for startup failures. A package
   already installed with a different signing identity may need an intentional uninstall, which deletes its local
   application data; do not uninstall it without user approval.

At completion, provide:

- changed files;
- implementation summary;
- build result;
- test result;
- known limitations.
