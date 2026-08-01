# UI and Interaction Contracts

## Scope

This document defines intentional product behavior for navigation, responsive layout, the mini player and the
full-player transition. Treat these as behavioral contracts, not implementation suggestions.

Do not weaken a contract merely to make an isolated gesture or layout test pass. When an intentional product change
is requested, update this document and the corresponding tests in the same change.

## Shared HDS chrome

- Use the HDS component family for project-level navigation chrome and material surfaces.
- Titles, back buttons, scrolling blur and secondary destinations come from shared navigation templates.
- Do not recreate project-level chrome independently inside feature pages.
- Preserve system material effects, pressed highlights, depth changes and smooth size transitions.
- Do not replace HDS glass with a flat translucent color.
- Prefer system Symbols when an appropriate icon exists.
- Use SVG resources for custom icons; do not use text characters as icons.

## Responsive navigation

### Compact layouts

- Use a floating horizontal HDS tab bar.
- The four primary pages are playlists, songs, albums and more.
- Destinations behind more remain secondary pages on that tab's controlled stack.
- Compact bottom-tab motion is governed by its own HdsTabs instance.

### Large and unfolded layouts

- Use a separate vertical HDS tab instance and controller.
- Omit the more tab and page.
- Expose compact-more destinations directly as root tabs without back buttons.
- Disable side-tab swipe navigation and HdsTabs page-transition animation.
- Allow the full navigation and mini player to remain visible on opposite sides.

Use a compact icon-over-label side bar in portrait unfolded layouts and a wider icon-beside-label side bar in
landscape. Keep portrait items centered. When landscape tab contents need a shared leading edge, keep the custom tab
builder inside HdsTabs.

The expanded HdsTabs owns its side frame and divider. Configure its built-in bar width and layout properties
directly; do not add wrapper margins, borders or replacement backgrounds.

### Breakpoint continuity

- Compact and expanded layouts use separate HdsTabs instances and controllers.
- An HdsTabsController must never control both instances.
- Keep each active TabContent collection structurally stable.
- Keep selection, route IDs, controlled stacks and durable page state outside responsive hosts.
- Define compact-more and expanded-side destinations in one shared registry.
- When crossing a breakpoint, promote the active compact secondary destination to an expanded root or demote the
  expanded root onto the compact more stack.
- Preserve page identity, durable state and coherent back behavior across the transition.

## Navigation stacks

- Navigation hosts live at the persistent-tab shell boundary.
- Each tab owns one controlled stack.
- Feature pages must not create private nested Navigation stacks.
- Persistent tabs and player controls remain above secondary destinations.
- Detail pages preserve the selected tab and floating chrome.

## Page layout

- Use edge-to-edge immersive layout with transparent system bars.
- Backgrounds may extend under system UI.
- Interactive content dynamically respects status, navigation-indicator and cutout avoid areas.
- Page backgrounds are edge-to-edge solid theme colors.
- Dark page backgrounds are AMOLED black.
- Outside theme accent and semantic status colors, use neutral grayscale tokens without blue-tinted neutrals.
- List, Grid and Scroll viewports cover the physical page.
- Use shared content start/end offsets so initial and final items remain readable behind floating chrome.
- Do not shrink a viewport with page-specific top or bottom padding.
- Content may pass beneath HDS title chrome.
- Use Spring edge effects and retain virtual-cache items beneath overlays.
- Keep short Scroll content top-aligned rather than vertically centered.
- Use responsive Grid policies or a shared layout specification; do not hard-code feature-page column counts.
- Album grids keep at least two equal-width columns; wider layouts retain the shared preferred minimum column width
  when deriving additional columns.

## Floating navigation and mini player

- Navigation and the mini player are separate rounded glass surfaces.
- On compact layouts, expanding one surface collapses the other to its current-page icon or album artwork.
- On unfolded layouts, both full surfaces may remain visible.
- Preserve the current HDS surface state when an interaction is cancelled or when returning from the full player.

## Mini-player gestures

Horizontal dragging:

- moves only track text;
- keeps album artwork and playback controls fixed;
- clips translated content to the rounded parent;
- may provide light threshold haptics;
- must not change tracks until that playback behavior is intentionally implemented.

Vertical dragging:

- upward movement expands the player interactively and follows the finger;
- release below threshold returns without overshoot;
- release above threshold completes expansion.

Taps:

- tapping expanded mini-player artwork or track text opens the full player;
- playback controls retain their own click behavior.

Gesture arbitration must preserve taps, horizontal drag and vertical drag together. Do not repair one gesture by
suppressing another.

## Full-player shared-element morph

- “保持屏幕常亮” defaults to disabled. When enabled, the foreground main window remains awake from the start of
  full-player opening until closing or cancellation reaches the idle phase; backgrounding or destroying the window
  releases the request.
- “歌词模糊效果” defaults to enabled. Disabling it keeps lyric follow, active-line emphasis and seeking behavior but
  renders every lyric line crisp. The existing drag-time suspension applies only while the preference is enabled.
- Use the two-pane full-player pager only for landscape viewports at least 720vp wide and tall enough to preserve
  visually dominant cover artwork; narrower or short windows retain the single-pane pager.
- Full-player cover layouts keep artwork visually dominant by sizing playback-button containers independently from
  their enlarged visible icons. Visible glyphs and metadata must remain clear of the cover.
- Full-player artwork preserves its source aspect ratio and expands within the remaining rectangular cover region;
  artwork with unknown dimensions uses a square fallback. List, grid and mini-player artwork retain their stable
  square geometry.
- Keep the full-player queue header actions visually compact with adjacent button containers and no inter-button
  gap while preserving the visible icon sizes.
- Render the current queue item with a flat, shadowless background that reaches both horizontal page edges. In
  two-pane layouts, fade the final 10% of that background to transparent at the trailing edge.
- Keep the active timed lyric crisp. During automatic follow, increase non-active blur symmetrically and linearly
  from the configured near-line radius to the configured far-line radius, then hold at the far radius. Suspend blur
  as soon as the user starts dragging the lyric list, then restore it when the lyric page becomes active again or
  when the next lyric-index update resumes automatic scrolling. Use compact spacing between regular lyric lines and
  preserve extra vertical breathing room around the active line. Put the blur clearance and line spacing inside each
  lyric text's padding, subtracting the same horizontal clearance from the lyrics container so the visible text inset
  remains stable.
- In regular full-player layouts, keep the collapse button at the leading top position. The cover region reserves
  only through the button's lower edge and adds no player-specific top offset beyond the system avoid area.
- Full-player lyrics and queue scroll viewports extend to the physical bottom edge. Apply the system bottom avoid
  inset as scroll-content end spacing so the final item remains reachable above system UI.
- Freeze source and destination geometry when a transition begins.
- Use one overlay artwork instance.
- Drive position, scale, corner radius and shadow from one progress value.
- Keep the final full-player canvas at final layout size.
- Animate the clipping shell rather than relaying out the full content tree every frame.
- Opening responds immediately.
- The overlay replaces the source surface without a fade-in.
- During close or cancellation, finish geometry before fading the replacement background.
- Fade only the replacement background to reveal real HDS glass.
- Remove replacement foreground and reveal real controls in the same final frame.
- Preserve the pre-transition mini-bar HDS state when returning.

## Album-artwork picture-in-picture

- “显示浮窗按钮” defaults to enabled. When enabled, the cover page keeps the action visible and disables it when no
  current track exists. When disabled, regular and ultra-compact cover layouts omit the action without reserving an
  empty slot; automatic floating-window behavior remains unchanged.
- Starting picture-in-picture is an explicit user action; returning the application to the background must not race
  the foreground-only PiP start request.
- The PiP content follows the current artwork aspect ratio and uses a square fallback when dimensions are missing.
- Track changes update both the PiP artwork and its content size.
- Use the system video-play PiP control panel for play/pause and previous/next; forward those actions to the one
  application PlaybackRuntime and synchronize system control state back from PlayerStore.
- “打开浮窗后的行为” offers do nothing, minimize the application and close the full-player page, defaulting to
  minimize. On desktop and 2-in-1 devices, minimize the main window through the window-management API after PiP
  starts; only fall back to moving the ability to the background when window minimization reports that the
  capability is unsupported. Closing the player page must not stop audio playback.
- “播放时最小化自动打开浮窗” defaults to disabled. When enabled, arm system PiP auto-start only while a current
  track is actively playing; pausing, clearing the current track or disabling the preference must disarm it.
- “何时自动关闭小窗” offers never, when the application returns to the foreground and when the full-player page
  opens, defaulting to the application-foreground trigger.
- PiP content is display-only. It does not create another playback engine or independently own playback state.

## Animation and rendering implementation

- Model multi-stage transitions with an explicit enum phase.
- Sequence stages through documented completion callbacks.
- Do not coordinate stages with unguarded `setTimeout`.
- Invalidate stale completions when newer input starts.
- Keep motion and layout constants in dedicated specification types.
- Aggregate geometry in frame or point objects.
- Isolate HDS geometry adaptation from rendering.
- Read changing observable state directly inside framework-owned Builders.
- Do not pass changing primitives through Builder parameters that may be captured.
- Prefer translate and scale transforms for interactive motion.
- Avoid layout-position changes for frame-by-frame animation.

## UI change completion

Use the applicable automated and manual cases from `TEST_MATRIX.md`. Rapid repeated input and both responsive hosts
are adjacent behavior for navigation or player transition changes, even when only one layout originally exposed the
defect.
