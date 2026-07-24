import {
  FullPlayerPage,
  FullPlayerPagerSpec,
  FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID,
  FULL_PLAYER_VERTICAL_GESTURE_HOST_ID,
  PlayerFrame,
  PlayerLayoutSpec,
  PlayerMotionSpec,
  PlayerPoint
} from './PlayerMotion';
import {
  PlayerModeAction,
  PlayerModeButton,
  PlayerPlaybackButton,
  PlayerTransportAction,
  PlayerTransportButton
} from './PlayerControls';
import { PlayerHeroArtwork } from './PlayerArtworkViews';
import {
  LyricIndexListener,
  PlaybackProgressStore,
  PlayerStore,
  QueueEntry,
  QueueTrack,
  QueueIndexListener
} from '../../playback/model/PlaybackModels';
import { TimedLyricLine } from '../../playback/lyrics/LyricsParser';
import { QueueTrackRow } from './QueueTrackRow';
import { LayoutLength } from '../layout/LayoutLength';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerTrackMarquee } from './PlayerTrackMarquee';
import { PageLayoutSpec } from '../layout/PageLayoutSpec';
import { LibraryStore } from '../../library/store/LibraryStore';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import {
  AvailabilityState,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';

@Reusable
@Component
struct TimedLyricRow {
  @ObjectLink playerStore: PlayerStore;
  @Prop line: TimedLyricLine;
  @Prop index: number = -1;

  build() {
    Text(this.line.text)
      .width('100%')
      .fontSize(23)
      .lineHeight(38)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.index === this.playerStore.activeLyricIndex ?
        this.playerStore.themeOnPrimary() : this.playerStore.themeOnPrimaryMedium())
      .animation({ duration: PlayerMotionSpec.LYRIC_FOCUS_DURATION, curve: Curve.EaseInOut })
      .opacity(this.index === this.playerStore.activeLyricIndex ? 1 : 0.72)
      .textAlign(TextAlign.Start)
      .scale({
        x: this.index === this.playerStore.activeLyricIndex ? 1 : 0.88,
        y: this.index === this.playerStore.activeLyricIndex ? 1 : 0.88,
        centerX: '0%',
        centerY: '50%'
      })
      .animation({ duration: PlayerMotionSpec.LYRIC_FOCUS_DURATION, curve: Curve.EaseInOut })
  }
}

@Component
struct PlayerProgressControl {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink progressStore: PlaybackProgressStore;
  onSeek: (positionMs: number) => void = (_positionMs: number): void => {};
  @State private seeking: boolean = false;
  @State private seekPreviewMs: number = 0;

  private durationLabel(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private displayedPositionMs(): number {
    if (this.seeking) {
      return this.seekPreviewMs;
    }
    return Math.max(0, Math.min(this.progressStore.positionMs, this.progressStore.durationMs));
  }

  private updateSeek(value: number, mode: SliderChangeMode): void {
    this.seekPreviewMs = Math.max(0, Math.min(value, this.progressStore.durationMs));
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.seeking = true;
      return;
    }
    this.seeking = false;
    this.onSeek(Math.round(this.seekPreviewMs));
  }

  build() {
    Column({ space: 2 }) {
      Slider({
        value: this.displayedPositionMs(),
        min: 0,
        max: Math.max(1, this.progressStore.durationMs),
        step: 1000,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .selectedColor(this.playerStore.themeOnPrimary())
        .trackColor(this.playerStore.themeOnPrimaryMedium())
        .blockColor(this.playerStore.themeOnPrimary())
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        .trackThickness(PlayerLayoutSpec.FULL_PLAYER_PROGRESS_TRACK_THICKNESS)
        .enabled(this.progressStore.durationMs > 0)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.updateSeek(value, mode);
        })
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) => {
          recognizers.forEach((recognizer: GestureRecognizer) => {
            const targetId = recognizer.getEventTargetInfo().getId();
            if (targetId === FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID ||
              targetId === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
              recognizer.preventBegin();
            }
          });
        })

      Row() {
        Text(this.durationLabel(this.displayedPositionMs()))
          .fontSize(11)
          .fontColor(this.playerStore.themeOnPrimaryMedium())
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        Blank()
        Text(this.durationLabel(this.progressStore.durationMs))
          .fontSize(11)
          .fontColor(this.playerStore.themeOnPrimaryMedium())
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      }
      .width('100%')
    }
    .width('100%')
    .margin({ top: 8 })
  }
}

@Component
export struct FullPlayerContent {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink libraryStore: LibraryStore;
  @Prop marqueeActive: boolean = true;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop showArtwork: boolean = true;
  @Prop showPlaybackButton: boolean = true;
  @Prop heroArtworkInterpolation: ImageInterpolation = ImageInterpolation.High;
  @Prop measuresArtworkTarget: boolean = false;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop pagePosition: number = FullPlayerPage.COVER;
  @Prop paneCount: number = 1;
  @Prop activePage: FullPlayerPage = FullPlayerPage.COVER;
  @Prop sideContentReady: boolean = true;
  @Prop primaryContentColor: string = '';
  @Prop previousArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  @Prop previousCenteredArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  onClose: () => void = (): void => {};
  onNavigatePage: (page: FullPlayerPage) => void = (_page: FullPlayerPage): void => {};
  onPlayQueueTrack: (trackId: number) => void = (_trackId: number): void => {};
  onSeek: (positionMs: number) => void = (_positionMs: number): void => {};
  onResolveQueueArtwork: (relativePath: string) => string = (_relativePath: string): string => '';
  onOpenTrackActions: (trackId: number, anchorId: string) => void =
    (_trackId: number, _anchorId: string): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};
  onCompletedCollectionChange: (enabled: boolean) => void =
    (_enabled: boolean): void => {};
  onArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  onCenteredArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  onPlaybackButtonTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};
  private readonly queueScroller: Scroller = new Scroller();
  private readonly lyricScroller: Scroller = new Scroller();
  private lastFocusedQueueIndex: number = -1;
  private lastFocusedLyricIndex: number = -1;
  @State private selectedQueueEntries: Array<QueueEntry> = [];
  @State private queueSelectionActive: boolean = false;
  private readonly queueIndexListener: QueueIndexListener = (index: number): void => {
    if (this.measuresArtworkTarget || index < 0 || this.playerStore.queueSize === 0) {
      return;
    }
    this.focusQueueIndex(index, true);
  };
  private readonly lyricIndexListener: LyricIndexListener = (index: number): void => {
    if (this.measuresArtworkTarget || index < 0 || this.playerStore.timedLyrics.length === 0) {
      return;
    }
    const targetIndex = Math.max(0, index - 2);
    this.lastFocusedLyricIndex = index;
    this.lyricScroller.scrollToIndex(targetIndex, true, ScrollAlign.START);
  };

  private queueEntrySelected(entryId: number): boolean {
    return this.selectedQueueEntries.some((entry: QueueEntry): boolean =>
      entry.queueEntryId === entryId);
  }

  private queueActionTrack(track: QueueTrack): TrackListItem {
    return {
      id: track.id,
      title: track.title,
      artistDisplay: track.artistDisplay,
      albumDisplay: track.albumDisplay,
      durationMs: track.durationMs,
      trackNumber: 0,
      discNumber: 0,
      smallArtworkHash: track.smallArtworkHash,
      smallArtworkPath: track.smallArtworkPath,
      artworkHash: track.largeArtworkHash,
      artworkPath: track.largeArtworkPath,
      artworkWidth: track.artworkWidth,
      artworkHeight: track.artworkHeight,
      palettePrimary: track.palettePrimary,
      paletteSecondary: track.paletteSecondary,
      paletteAccent: track.paletteAccent,
      sectionKey: '',
      availability: AvailabilityState.AVAILABLE
    };
  }

  private toggleQueueSelection(entry: QueueEntry): void {
    if (this.queueEntrySelected(entry.queueEntryId)) {
      this.selectedQueueEntries =
        this.selectedQueueEntries.filter((selected: QueueEntry): boolean =>
          selected.queueEntryId !== entry.queueEntryId);
    } else {
      this.selectedQueueEntries = this.selectedQueueEntries.concat([entry]);
    }
  }

  private cancelQueueSelection(): void {
    this.queueSelectionActive = false;
    this.selectedQueueEntries = [];
  }

  @Builder
  private QueueSelectionMenu() {
    Menu() {
      MenuItem({ content: '播放' })
        .onClick(() => {
          playbackRuntime.playQueueSelection(
            this.selectedQueueEntries.map((entry: QueueEntry) => entry.track)
          );
          this.cancelQueueSelection();
        })
      MenuItem({ content: '添加到播放列表' })
        .onClick(() => this.onRequestAddToPlaylist(
          this.selectedQueueEntries.map((entry: QueueEntry): number => entry.track.id)
        ))
      MenuItem({ content: '插播', labelInfo: '下一首开始' })
        .onClick(() => playbackRuntime.insertQueueTracks(
          this.selectedQueueEntries.map((entry: QueueEntry) => entry.track)
        ))
      MenuItem({ content: '追加到播放队列' })
        .onClick(() => playbackRuntime.appendQueueTracks(
          this.selectedQueueEntries.map((entry: QueueEntry) => entry.track)
        ))
      MenuItem({ content: '从播放队列移除' })
        .onClick(() => {
          playbackRuntime.removeQueueEntries(
            this.selectedQueueEntries.map((entry: QueueEntry): number => entry.queueEntryId)
          );
          this.cancelQueueSelection();
        })
    }
    .width(240)
  }

  @Builder
  private CurrentTrackMenu() {
    Menu() {
      MenuItem({ content: '插播', labelInfo: '下一首开始' })
        .enabled(this.playerStore.currentTrack !== undefined)
        .onClick(() => playbackRuntime.insertCurrentNext())
      MenuItem({ content: '追加到队列' })
        .enabled(this.playerStore.currentTrack !== undefined)
        .onClick(() => playbackRuntime.appendCurrentToQueue())
      MenuItem({ content: '添加到播放列表' })
        .enabled(this.playerStore.currentTrack !== undefined)
        .onClick(() => {
          if (this.playerStore.currentTrack !== undefined) {
            this.onRequestAddToPlaylist([this.playerStore.currentTrack.id]);
          }
        })
      MenuItem({ content: '文件信息' })
        .enabled(this.playerStore.currentTrack !== undefined)
        .onClick(() => {
          if (this.playerStore.currentTrack !== undefined) {
            this.onOpenTrackDetails(this.queueActionTrack(this.playerStore.currentTrack));
          }
        })
      MenuItem({
        content: '收集完整听过的音乐',
        symbolEndIcon: this.playerStore.completedCollectionEnabled ?
          new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          this.onCompletedCollectionChange(!this.playerStore.completedCollectionEnabled);
        })
    }
    .width(260)
  }

  private pageWidth(): number {
    return FullPlayerPagerSpec.pageSpan(this.rootFrame.width, this.paneCount);
  }

  private artworkSlotSize(): number {
    return PlayerLayoutSpec.fullArtworkSize(
      this.pageWidth(),
      this.rootFrame.height,
      this.topInset,
      this.bottomInset
    );
  }

  private currentArtistLabel(): string {
    if (this.playerStore.currentTrack === undefined) {
      return '选择一首音乐开始播放';
    }
    return this.playerStore.currentTrack.artistDisplay.trim().length > 0 ?
      this.playerStore.currentTrack.artistDisplay : '未知艺术家';
  }

  private currentTitleLabel(): string {
    return this.playerStore.currentTrack?.title ?? '尚未播放';
  }

  private contentColor(): string {
    return this.primaryContentColor.length > 0 ?
      this.primaryContentColor : this.playerStore.themeOnPrimary();
  }

  private pageButtonDisabled(page: FullPlayerPage): boolean {
    const currentPosition = Math.round(
      FullPlayerPagerSpec.clampPosition(this.pagePosition, this.paneCount)
    );
    return currentPosition === FullPlayerPagerSpec.positionForPage(page, this.paneCount);
  }

  private isPageInActiveViewport(page: FullPlayerPage): boolean {
    if (this.paneCount > 1) {
      const startPosition = FullPlayerPagerSpec.positionForPage(this.activePage, this.paneCount);
      return page >= startPosition && page < startPosition + this.paneCount;
    }
    return page === this.activePage;
  }

  private shouldRenderPage(page: FullPlayerPage): boolean {
    return this.sideContentReady || this.isPageInActiveViewport(page);
  }

  aboutToAppear(): void {
    if (!this.measuresArtworkTarget) {
      this.playerStore.addQueueIndexListener(this.queueIndexListener);
      this.playerStore.addLyricIndexListener(this.lyricIndexListener);
    }
  }

  aboutToDisappear(): void {
    if (!this.measuresArtworkTarget) {
      this.playerStore.removeQueueIndexListener(this.queueIndexListener);
      this.playerStore.removeLyricIndexListener(this.lyricIndexListener);
    }
  }

  private focusQueueIndex(index: number, animated: boolean): void {
    this.lastFocusedQueueIndex = index;
    this.queueScroller.scrollToIndex(index, animated, ScrollAlign.START);
  }

  onDidBuild(): void {
    if (this.measuresArtworkTarget) {
      return;
    }
    if (this.sideContentReady &&
      this.shouldRenderPage(FullPlayerPage.QUEUE) &&
      this.playerStore.queueCurrentIndex >= 0 &&
      this.lastFocusedQueueIndex !== this.playerStore.queueCurrentIndex) {
      this.focusQueueIndex(this.playerStore.queueCurrentIndex, false);
    }
    if (!this.shouldRenderPage(FullPlayerPage.LYRICS)) {
      return;
    }
    const lyricIndex = this.playerStore.activeLyricIndex;
    if (this.playerStore.timedLyrics.length === 0) {
      this.lastFocusedLyricIndex = -1;
    }
    if (lyricIndex >= 0 && lyricIndex !== this.lastFocusedLyricIndex) {
      this.lastFocusedLyricIndex = lyricIndex;
      this.lyricIndexListener(lyricIndex);
    }
  }

  private lyricEndOffset(): number {
    return Math.max(0, (this.rootFrame.height - this.topInset - this.bottomInset) * 0.62);
  }

  private headerTextInset(page: FullPlayerPage): number {
    if (this.paneCount === 1 || page === FullPlayerPage.QUEUE) {
      return PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET +
        PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE + PlayerLayoutSpec.FULL_PLAYER_HEADER_TEXT_GAP;
    }
    return PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET;
  }

  @Builder
  private Header() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 0 }) {
        if (this.shouldRenderPage(FullPlayerPage.QUEUE)) {
          this.QueueHeader()
        } else {
          Stack().width(this.pageWidth()).height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        }
        Stack().width(this.pageWidth()).height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        if (this.shouldRenderPage(FullPlayerPage.LYRICS)) {
          this.LyricsHeader()
        } else {
          Stack().width(this.pageWidth()).height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        }
      }
      .width(this.pageWidth() * FullPlayerPagerSpec.PAGE_COUNT)
      .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
      .translate({ x: -this.pagePosition * this.pageWidth() })

      Row() {
        Stack() {
          Image($r('app.media.control_chevron_down'))
            .width(PlayerLayoutSpec.FULL_PLAYER_CLOSE_ICON_SIZE)
            .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_ICON_SIZE)
            .fillColor(this.contentColor())
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        }
        .width(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        .borderRadius(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE / 2)
        .backgroundColor($r('app.color.glass_surface_subtle'))
        .clickEffect({ level: ClickEffectLevel.MIDDLE })
        .accessibilityText('收起播放器')
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .padding({
        left: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET,
        right: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET
      })
    }
    .width('100%')
    .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
    .clip(true)
  }

  @Builder
  private QueueHeader() {
    Row({ space: 8 }) {
      Text('当前播放队列')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.playerStore.themeOnPrimary())
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.queueSelectionActive) {
        Button(`操作 ${this.selectedQueueEntries.length}`)
          .height(40)
          .enabled(this.selectedQueueEntries.length > 0)
          .fontColor(this.playerStore.themeOnPrimary())
          .backgroundColor($r('app.color.glass_surface_subtle'))
          .bindMenu(this.QueueSelectionMenu(), { placement: Placement.BottomRight })
        Button('取消')
          .height(40)
          .fontColor(this.playerStore.themeOnPrimary())
          .backgroundColor(Color.Transparent)
          .onClick(() => this.cancelQueueSelection())
      } else {
        Text(`${this.playerStore.queueSize} 首`)
          .fontSize(13)
          .fontColor(this.playerStore.themeOnPrimaryMedium())
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        PlayerModeButton({
          playerStore: this.playerStore,
          action: PlayerModeAction.SHUFFLE,
          buttonSize: 44
        })
        PlayerModeButton({
          playerStore: this.playerStore,
          action: PlayerModeAction.REPEAT,
          buttonSize: 44
        })
        Button() {
          SymbolGlyph($r('sys.symbol.checkmark_square_on_square'))
            .fontSize(21)
            .fontColor([this.playerStore.themeOnPrimary()])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor($r('app.color.glass_surface_subtle'))
        .accessibilityText('多选')
        .onClick(() => {
          this.queueSelectionActive = true;
          this.selectedQueueEntries = [];
        })
      }
    }
    .width(this.pageWidth())
    .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
    .padding({
      left: this.headerTextInset(FullPlayerPage.QUEUE),
      right: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET
    })
  }

  @Builder
  private PageNavigationButton(page: FullPlayerPage) {
    Stack() {
      SymbolGlyph(page === FullPlayerPage.QUEUE ?
        $r('sys.symbol.music_note_list_fill') : $r('sys.symbol.lyrics_square'))
        .fontSize(22)
        .fontColor([this.contentColor()])
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor($r('app.color.glass_surface_subtle'))
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .enabled(!this.pageButtonDisabled(page))
    .opacity(this.pageButtonDisabled(page) ? 0.38 : 1)
    .accessibilityText(page === FullPlayerPage.QUEUE ? '打开播放队列' : '打开歌词')
    .onClick(() => {
      this.onNavigatePage(page);
    })
  }

  @Builder
  private LyricsHeader() {
    Column({ space: 2 }) {
      if (this.paneCount === 1) {
        Text(this.playerStore.currentTrack?.title ?? '尚未播放')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.playerStore.themeOnPrimary())
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          .maxLines(1)
        Text(this.currentArtistLabel())
          .fontSize(12)
          .fontColor(this.playerStore.themeOnPrimaryMedium())
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width(this.pageWidth())
    .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
    .padding({
      left: this.headerTextInset(FullPlayerPage.LYRICS),
      right: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET
    })
  }

  @Builder
  private QueuePage() {
    Stack({ alignContent: Alignment.Bottom }) {
    Column() {
      if (this.playerStore.queueSize === 0) {
        Column({ space: 8 }) {
          Text('队列为空')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.playerStore.themeOnPrimary())
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          Text('从音乐库选择歌曲后会显示在这里')
            .fontSize(14)
            .fontColor(this.playerStore.themeOnPrimaryMedium())
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        }
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .width('100%')
      } else {
        List({ space: 0, scroller: this.queueScroller }) {
          LazyForEach(this.playerStore.queueDataSource, (entry: QueueEntry, index: number) => {
            ListItem() {
              Column() {
                if (index > 0) {
                  Divider()
                    .strokeWidth(PlayerLayoutSpec.FULL_PLAYER_QUEUE_DIVIDER_HEIGHT)
                    .color(this.playerStore.themeOnPrimaryMedium())
                    .opacity(PlayerLayoutSpec.FULL_PLAYER_QUEUE_DIVIDER_OPACITY)
                    .margin({
                      left: PlayerLayoutSpec.FULL_PLAYER_QUEUE_INDEX_WIDTH +
                        PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE + 20 +
                        PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
                      right: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET
                    })
                }
                Row() {
                  QueueTrackRow({
                    track: this.queueActionTrack(entry.track),
                    store: this.libraryStore,
                    artworkPath: this.onResolveQueueArtwork(entry.track.smallArtworkPath),
                    queueIndex: index,
                    currentQueueIndex: this.playerStore.queueCurrentIndex,
                    primaryColor: this.playerStore.themeOnPrimary(),
                    secondaryColor: this.playerStore.themeOnPrimaryMedium(),
                    tertiaryColor: this.playerStore.themeOnPrimaryMedium(),
                    animateColors: true,
                    active: entry.track.id === this.playerStore.currentTrack?.id,
                    activeBackgroundColor: $r('app.color.glass_surface_strong'),
                    activeShadowColor: $r('app.color.artwork_shadow'),
                    activeShadowRadius: PlayerLayoutSpec.FULL_PLAYER_QUEUE_SHADOW_RADIUS,
                    activeShadowOffsetY: PlayerLayoutSpec.FULL_PLAYER_QUEUE_SHADOW_OFFSET_Y,
                    horizontalInset: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
                    verticalInset: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ROW_VERTICAL_INSET,
                    rowCornerRadius: 14,
                    artworkSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE,
                    artworkCornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
                    queueIndexWidth: PlayerLayoutSpec.FULL_PLAYER_QUEUE_INDEX_WIDTH,
                    queueGestureDistance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE,
                    menuPlacement: Placement.BottomLeft,
                    onNavigateAction: this.onNavigateLibrary,
                    onRequestAddToPlaylist: (items: Array<TrackListItem>): void =>
                      this.onRequestAddToPlaylist(items.map((item: TrackListItem): number => item.id)),
                    onOpenDetails: (track: TrackListItem): void =>
                      this.onOpenTrackDetails(track),
                    selectionMode: this.queueSelectionActive,
                    selected: this.queueEntrySelected(entry.queueEntryId),
                    onActivate: (track: TrackListItem): void => {
                      this.onPlayQueueTrack(track.id);
                    },
                    onToggleSelection: (_track: TrackListItem): void =>
                      this.toggleQueueSelection(entry)
                  })
                    .reuseId(this.queueSelectionActive ?
                      'player_queue_selection' : 'player_queue_track')
                }
                .width('100%')
                .padding({
                  left: PlayerLayoutSpec.FULL_PLAYER_QUEUE_SHADOW_CLEARANCE,
                  right: PlayerLayoutSpec.FULL_PLAYER_QUEUE_SHADOW_CLEARANCE
                })
              }
              .width('100%')
            }
            .height(PlayerLayoutSpec.FULL_PLAYER_QUEUE_ITEM_HEIGHT)
          }, (entry: QueueEntry) => `${entry.queueEntryId}`)
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(LibraryPagingPolicy.TRACK_PAGE_SIZE, true)
        .scrollBar(BarState.Auto)
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) => {
          recognizers.forEach((recognizer: GestureRecognizer) => {
            if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
              recognizer.preventBegin();
            }
          });
        })
      }
    }
    .width(this.pageWidth())
    .height('100%')
    .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) => {
      recognizers.forEach((recognizer: GestureRecognizer) => {
        if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
          recognizer.preventBegin();
        }
      });
    })
    .padding({
      top: PlayerLayoutSpec.FULL_PLAYER_PAGE_TOP_INSET +
        (this.paneCount > 1 ? PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE : 0),
      bottom: this.bottomInset + PlayerLayoutSpec.FULL_PLAYER_BOTTOM_INSET
    })
    }
    .width(this.pageWidth())
    .height('100%')
  }

  @Builder
  private CoverPage() {
    Column() {
      Blank().layoutWeight(1)

      Stack() {
        if (this.showArtwork) {
          PlayerHeroArtwork({
            playerStore: this.playerStore,
            slotSize: this.artworkSlotSize(),
            cornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
            interpolation: this.heroArtworkInterpolation
          })
        }
      }
      .width(this.artworkSlotSize())
      .height(this.artworkSlotSize())
      .borderRadius(this.artworkSlotSize() / 2)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        if (!this.measuresArtworkTarget) {
          return;
        }
        const pageWidth = this.pageWidth();
        const layoutTarget: PlayerPoint = {
          x: LayoutLength.toNumber(
            newValue.globalPosition.x,
            this.previousCenteredArtworkTarget.x + this.rootFrame.x
          ) - this.rootFrame.x,
          y: LayoutLength.toNumber(
            newValue.globalPosition.y,
            this.previousArtworkTarget.y + this.rootFrame.y
          ) - this.rootFrame.y
        };
        const centeredTarget: PlayerPoint = {
          x: layoutTarget.x,
          y: layoutTarget.y
        };
        this.onCenteredArtworkTarget(centeredTarget);
        this.onArtworkTarget({
          x: FullPlayerPagerSpec.pagerArtworkTargetX(
            centeredTarget.x,
            this.pagePosition,
            pageWidth
          ),
          y: centeredTarget.y
        });
      })

      Blank().layoutWeight(1)

      Column({ space: 5 }) {
        Row({ space: 8 }) {
          if (this.measuresArtworkTarget) {
            Text(this.currentTitleLabel())
              .fontSize(PlayerLayoutSpec.FULL_PLAYER_TITLE_SIZE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.contentColor())
              .maxLines(1)
              .layoutWeight(1)
          } else {
            PlayerTrackMarquee({
              playerStore: this.playerStore,
              active: this.marqueeActive,
              titleColor: this.contentColor(),
              titleSize: PlayerLayoutSpec.FULL_PLAYER_TITLE_SIZE,
              titleWeight: FontWeight.Bold,
              animateColor: true
            })
              .layoutWeight(1)
          }

          Stack() {
            Image($r('app.media.control_more'))
              .width(20)
              .height(20)
              .fillColor(this.contentColor())
              .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface_subtle'))
          .clickEffect({ level: ClickEffectLevel.MIDDLE })
          .accessibilityText('更多操作')
          .bindMenu(this.CurrentTrackMenu(), { placement: Placement.BottomRight })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.measuresArtworkTarget) {
          Text(this.currentArtistLabel())
            .fontSize(PlayerLayoutSpec.FULL_PLAYER_ARTIST_SIZE)
            .fontColor(this.playerStore.themeOnPrimaryMedium())
            .maxLines(1)
        } else {
          Text(this.currentArtistLabel())
            .fontSize(PlayerLayoutSpec.FULL_PLAYER_ARTIST_SIZE)
            .fontColor(this.playerStore.themeOnPrimaryMedium())
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
            .maxLines(1)
            .id('full_player_artist_action')
            .accessibilityText('查看艺术家、专辑艺术家或专辑')
            .onClick(() => {
              if (this.playerStore.currentTrack !== undefined) {
                this.onOpenTrackActions(
                  this.playerStore.currentTrack.id,
                  'full_player_artist_action'
                );
              }
            })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      PlayerProgressControl({
        playerStore: this.playerStore,
        progressStore: this.playerStore.progress,
        onSeek: (positionMs: number): void => this.onSeek(positionMs)
      })

      Stack() {
        Row() {
          this.PageNavigationButton(FullPlayerPage.QUEUE)
          Blank()
          this.PageNavigationButton(FullPlayerPage.LYRICS)
        }
        .width('100%')
        .align(Alignment.Center)

        Row({ space: 16 }) {
          PlayerTransportButton({ playerStore: this.playerStore,
            action: PlayerTransportAction.PREVIOUS, buttonSize: 52,
            contentColor: this.contentColor() })
          PlayerPlaybackButton({
            playerStore: this.playerStore,
            buttonSize: PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE
          })
            .opacity(this.showPlaybackButton ? 1 : 0)
            .enabled(this.showPlaybackButton)
            .onAreaChange((_oldValue: Area, newValue: Area) => {
              if (!this.measuresArtworkTarget) {
                return;
              }
              this.onPlaybackButtonTarget({
                x: LayoutLength.toNumber(
                  newValue.globalPosition.x,
                  this.rootFrame.x
                ) - this.rootFrame.x,
                y: LayoutLength.toNumber(
                  newValue.globalPosition.y,
                  this.rootFrame.y
                ) - this.rootFrame.y,
                width: LayoutLength.toNumber(
                  newValue.width,
                  PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE
                ),
                height: LayoutLength.toNumber(
                  newValue.height,
                  PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE
                )
              });
            })
          PlayerTransportButton({ playerStore: this.playerStore,
            action: PlayerTransportAction.NEXT, buttonSize: 52,
            contentColor: this.contentColor() })
        }
        .align(Alignment.Center)
      }
      .height(64)
      .width('100%')
      .margin({ top: 18, bottom: 12 })
    }
    .width(this.pageWidth())
    .height('100%')
    .padding({
      left: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET,
      bottom: this.bottomInset + PlayerLayoutSpec.FULL_PLAYER_BOTTOM_INSET
    })
  }

  @Builder
  private LyricsPage() {
    Column() {
      if (this.playerStore.timedLyrics.length > 0) {
        List({ space: 14, scroller: this.lyricScroller }) {
          LazyForEach(this.playerStore.lyricDataSource, (line: TimedLyricLine, index: number) => {
            ListItem() {
              TimedLyricRow({ playerStore: this.playerStore, line: line, index: index })
                .reuseId('timed_lyric')
            }
          }, (line: TimedLyricLine, index: number) => `${line.timeMs}_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(LibraryPagingPolicy.TRACK_PAGE_SIZE, true)
        .scrollBar(BarState.Off)
        .contentEndOffset(this.lyricEndOffset())
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) => {
          recognizers.forEach((recognizer: GestureRecognizer) => {
            if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
              recognizer.preventBegin();
            }
          });
        })
      } else if (this.playerStore.lyrics.length > 0) {
        Scroll() {
          Text(this.playerStore.lyrics)
            .width('100%')
            .fontSize(20)
            .lineHeight(34)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.playerStore.themeOnPrimary())
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) => {
          recognizers.forEach((recognizer: GestureRecognizer) => {
            if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
              recognizer.preventBegin();
            }
          });
        })
      } else {
        Column({ space: 10 }) {
          Text('暂未找到内嵌歌词')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.playerStore.themeOnPrimary())
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          Text('当前仅读取音乐文件内部的歌词文本')
            .fontSize(14)
            .fontColor(this.playerStore.themeOnPrimaryMedium())
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
            .textAlign(TextAlign.Center)
        }
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width(this.pageWidth())
    .height('100%')
    .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) => {
      if (this.playerStore.timedLyrics.length === 0 && this.playerStore.lyrics.length === 0) {
        return;
      }
      recognizers.forEach((recognizer: GestureRecognizer) => {
        if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
          recognizer.preventBegin();
        }
      });
    })
    .padding({
      left: PlayerLayoutSpec.FULL_PLAYER_LYRICS_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.FULL_PLAYER_LYRICS_HORIZONTAL_INSET,
      top: this.paneCount > 1 ? 0 : PlayerLayoutSpec.FULL_PLAYER_PAGE_TOP_INSET,
      bottom: this.bottomInset + PlayerLayoutSpec.FULL_PLAYER_BOTTOM_INSET
    })
  }

  @Builder
  private PlayerPages() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 0 }) {
        if (this.shouldRenderPage(FullPlayerPage.QUEUE)) {
          this.QueuePage()
        } else {
          Stack().width(this.pageWidth()).height('100%')
        }
        this.CoverPage()
        if (this.shouldRenderPage(FullPlayerPage.LYRICS)) {
          this.LyricsPage()
        } else {
          Stack().width(this.pageWidth()).height('100%')
        }
      }
      .width(this.pageWidth() * FullPlayerPagerSpec.PAGE_COUNT)
      .height('100%')
      .translate({ x: -this.pagePosition * this.pageWidth() })
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  build() {
    if (this.measuresArtworkTarget) {
      Column() {
        Stack().height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        Stack({ alignContent: Alignment.TopStart }) {
          this.CoverPage()
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topInset + PlayerLayoutSpec.FULL_PLAYER_TOP_INSET })
    } else if (this.paneCount > 1) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.PlayerPages()
        this.Header()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topInset + PlayerLayoutSpec.FULL_PLAYER_TOP_INSET })
    } else {
      Column() {
        this.Header()
        Stack() {
          this.PlayerPages()
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topInset + PlayerLayoutSpec.FULL_PLAYER_TOP_INSET })
    }
  }
}
