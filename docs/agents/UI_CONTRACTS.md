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
- Artist details show bounded song and album previews. Their “view all” actions open collection destinations whose
  lists are independently paged and virtualized.
- Album details show related albums as a bounded, two-row horizontal preview. “View all” opens an independently
  paged album collection destination and keeps the current tab stack and floating chrome.

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
- When an alphabet index is visible, combine the page's existing trailing inset with only the additional gutter
  needed to clear the index track; the index must not cover row actions, text or album artwork or create a wide
  empty strip.
- Root and collection album grids declare regular item sizing, use virtualized slots and render large album artwork.
  Album-card shadows are omitted in high-density scrolling surfaces.
- Entering selection mode keeps reusable row/card identity and its content subtree stable. Only the leading
  selection slot and indicator animate; artwork and text must not fade or be reconstructed during the transition.
- In selection mode, a vertical pan that starts on a row's selection indicator previews a contiguous range from
  the anchor row to the current row. A horizontal pan that starts on album artwork previews the same range in the
  grid's display order, like Shift selection, including intervening cells at row boundaries. Moving back toward
  the anchor shrinks the preview; the actual selection changes only when the gesture ends. The anchor item's state
  determines whether the range is added or cleared. Pans that start outside these explicit targets retain normal
  scrolling behavior.

## Floating navigation and mini player

- Navigation and the mini player are separate rounded glass surfaces.
- On compact layouts, expanding one surface collapses the other to its current-page icon or album artwork.
- On unfolded layouts, both full surfaces may remain visible.
- Preserve the current HDS surface state when an interaction is cancelled or when returning from the full player.

## Mini-player gestures

Horizontal dragging:

- pages the track-information region through the previous, current and next entries in active playback order;
- keeps album artwork and playback controls fixed;
- clips adjacent track information to the rounded parent;
- may provide light threshold haptics;
- changes tracks only after an available adjacent page completes its settle; an unavailable edge returns with
  resistance and does not change playback.

Vertical dragging:

- upward movement expands the player interactively and follows the finger;
- release below threshold returns without overshoot;
- release above threshold completes expansion.

Taps:

- tapping expanded mini-player artwork or track text opens the full player;
- playback controls retain their own click behavior.

Gesture arbitration must preserve taps, horizontal drag and vertical drag together. Do not repair one gesture by
suppressing another.

## Music-file actions

- Single-track action menus expose “分享音乐文件” next to file information, including library rows, playlist rows,
  queue rows and the current-track menu.
- Sharing hands the original Picker-authorized music-file URI to the system share panel. It must not copy the audio
  into application storage or derive a physical path from the URI.
- Missing tracks, unavailable original URIs and revoked authorization fail without opening an invalid share panel
  and provide a concise user-facing message.

## Import range selection

- When the picked URIs all share one parent directory, import proceeds directly without a range-selection step.
- Otherwise the import session pauses after preflight and presents a directory tree rooted at the earliest
  diverging directory. Directories use a tri-state indicator (all, partial, none) derived from descendant file
  selection; the tree starts fully selected.
- Read permission is persisted only for the URIs the user confirms. Unselected URIs are never persisted, and
  cancelling the tree abandons the import before any permission is persisted.
- Exception to the opaque-URI rule: URI path segments may be decoded and grouped only to build this
  presentation tree. They must never be used to access the file system, and file metadata continues to come from
  the metadata reader, not from URI parsing.

## Playback queue and shuffle

- Enabling or disabling shuffle keeps the exact current queue entry active, including when the same track appears
  more than once.
- Shuffle changes only the playback permutation. Disabling it restores the queue's stable base order without
  discarding insertions, appends or removals made while shuffle was enabled.
- Queue restoration preserves base order, playback permutation, cursor and shuffle mode together. A valid persisted
  queue snapshot is authoritative over the fallback shuffle preference.
- “播放所选” follows the manual-play shuffle preference: by default it disables shuffle and preserves selection
  order; when “手动选歌时保持随机” is enabled it builds a matching shuffled traversal and state.
- The queue page displays active playback order, so shuffle visibly reorders rows and their relative position
  numbers. Pure permutations update the order behind stable position slots without RELOAD, EXCHANGE or full-list
  CHANGE notifications. Slot leaves resolve the current queue entry; shuffle must not open an implicit animation
  transaction anywhere in the mounted full-player tree.
- Tapping the queue-page shuffle control removes the complete queue list before changing the permutation. While the
  ordered database write is pending, the queue content area shows the platform `LoadingProgress` centered in the
  available space and ignores further queue mode input. After completion or failure, the list is rebuilt with
  `Visibility.Hidden`, positioned at the current item with non-animated scrolling, and revealed on the following
  frame. Persistence failure does not roll back the in-memory queue and must not leave the page in loading state.

## Full-player shared-element morph

- “沉浸模式”默认开启。开启时，点击稳定显示的播放封面进入沉浸展示；顶部返回区域向上退出，
  标题、进度与播放控制向下退出，封面舞台扩展到整个播放页。再次点击封面或按返回键先退出
  沉浸展示，不直接关闭播放页。关闭该设置后，点击封面不进入沉浸展示。
- 播放封面使用连续的队列分页容器，内部横向拖动可按当前播放顺序移动到任意相邻歌曲；通过播放控制、
  队列或自然结束切歌时，分页容器自动滚动到新的当前歌曲。分页以唯一队列项身份校验落页和异步回调，
  队列重排后无动画重新定位当前项；每张图片保留普通与沉浸可用矩形中的自适应宽高比。mini-player 与
  播放页封面横滑均保持切歌前的播放或暂停意图。关闭循环及单曲循环在队列边界停住；全部循环允许首尾
  封面连续互相切换。手势松手和非封面操作触发的自动切歌共用同一条轻微弹性分页曲线；远距离跳转仅
  动画滚动最后一段，不依次加载沿途封面。快速连续的非封面切歌不得重入正在进行的原生分页动画；
  当前分页落稳后仅继续滚动到期间收到的最新歌曲，并保持两段动画之间的滚动视觉状态连续。
- 动态背景的每次封面过渡都从当前实际呈现帧开始。新切歌在上一段过渡完成前到达时，先固化正在显示的
  混合帧，再从该帧向新封面过渡；不得跳到上一段过渡的目标背景。普通切歌和中断切歌使用同一快照路径。
- 播放页封面分页裁剪在当前封面 viewport 内；双栏横滑期间，左右边缘使用与页面水平内边距等宽的
  alpha 渐变遮罩并透出其下的动态背景，邻页封面不得覆盖队列或歌词。分页裁剪为封面阴影保留纵向
  绘制空间；横滑命中区保持在封面本体，不通过改变封面的上下内外边距来调整手势范围。边缘遮罩只在
  封面分页实际移动时启用，由 Swiper 的手势/动画生命周期显式控制；稳定态和播放页外层翻页不
  保留整块封面区域的离屏合成。相邻封面页之间保留独立间距，宽封面和阴影不得在当前滚动窗口边缘
  露出。
- 沉浸进入、退出和封面分页均可由新输入从当前呈现位置接管。沉浸期间禁用下拉关闭。单栏允许从
  封面页向右移动到歌词页，但不允许向左进入队列；封面内横滑仍优先切歌。返回键在歌词页先回到
  沉浸封面，再退出沉浸，之后才关闭播放器。
- “宽屏沉浸时显示歌词”默认开启。开启时，双栏沉浸以歌词加载状态决定布局：歌词加载中保持上一次
  已解析布局；有歌词时封面占左半屏且歌词保留在右半屏，无歌词时歌词侧退出、封面动画扩展到整个
  播放页。切歌不得因加载中的空歌词产生一次全屏再回半屏的中间动画。关闭后，宽屏沉浸固定使用
  封面全屏布局，不以歌词是否可用改变布局或显示歌词。
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
- Use one artwork actor for the mini/full shared-element morph. Stable full-player queue pages are separate from
  that morph actor. Keep only this actor mounted and transparent while the player is idle so the current artwork is
  prepared before opening; do not keep full-player content, the artwork pager or its gesture layer alive. Stable
  pages hand off only after the selected page is ready. When closing from a stable player, keep the selected pager
  page behind the closing actor until that actor's image is ready, then remove the pager in one frame.
- During opening, prepare only the selected artwork page required for the actor handoff. Enable adjacent artwork
  caching on the first stable frame after the pager is visible. Keep outer player-page motion as one pager-container
  transform; do not relay out every cached artwork page for each drag frame. Keep immersive geometry reactive through
  a narrow shared visual binding so cached pages retain the enter, exit and lyric-split size transitions. The current
  page follows the progressively upgraded full hero artwork; neighboring pages use cached large thumbnails until
  selected. Selecting a page must retain its actor revision when the current hero source is the same PixelMap or URI
  it already displays; only a materially different full-artwork source may replace that surface.
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
