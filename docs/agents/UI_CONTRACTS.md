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

- Use the two-pane full-player pager only for landscape viewports at least 720vp wide and tall enough to preserve
  visually dominant cover artwork; narrower or short windows retain the single-pane pager.
- Full-player cover layouts keep artwork visually dominant by sizing playback-button containers independently from
  their enlarged visible icons. Visible glyphs and metadata must remain clear of the cover.
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
