import {
  FullPlayerLayoutMode,
  FullPlayerPage,
  FullPlayerPagerSpec,
  PlayerFrame,
  PlayerLayoutSpec
} from './PlayerMotion';
import { PlayerImageIcon } from './PlayerControls';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { DynamicColor, ForegroundEmphasis } from '../../appearance/DynamicColor';
import { PageLayoutSpec } from '../layout/PageLayoutSpec';
import { LibraryStore } from '../../library/store/LibraryStore';
import {
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { FullPlayerCoverPage } from './FullPlayerCoverPage';
import { FullPlayerLyricsPage } from './FullPlayerLyricsPage';
import {
  FullPlayerQueueHeader,
  FullPlayerQueuePage,
  FullPlayerQueueSelectionStore
} from './FullPlayerQueuePage';
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';

@Component
export struct FullPlayerContent {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink libraryStore: LibraryStore;
  @Prop marqueeActive: boolean = true;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop showArtwork: boolean = true;
  @Prop showPlaybackButton: boolean = true;
  @Prop measuresArtworkTarget: boolean = false;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop pagePosition: number = FullPlayerPage.COVER;
  @Prop paneCount: number = 1;
  @Prop activePage: FullPlayerPage = FullPlayerPage.COVER;
  @Prop sideContentReady: boolean = true;
  @Prop pageScrollingEnabled: boolean = true;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop artworkSourceWidth: number = 0;
  @Prop artworkSourceHeight: number = 0;
  @Prop previousArtworkFrame: PlayerFrame = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y,
    width: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
    height: PlayerLayoutSpec.FULL_ARTWORK_SIZE
  };
  @Prop previousCenteredArtworkFrame: PlayerFrame = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y,
    width: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
    height: PlayerLayoutSpec.FULL_ARTWORK_SIZE
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
  onArtworkTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};
  onCenteredArtworkTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};
  onPlaybackButtonTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};
  @State private queueSelectionStore: FullPlayerQueueSelectionStore =
    new FullPlayerQueueSelectionStore();

  private pageWidth(): number {
    return FullPlayerPagerSpec.pageSpan(this.rootFrame.width, this.paneCount);
  }

  private isUltraCompact(): boolean {
    return PlayerLayoutSpec.fullPlayerLayoutMode(
      this.rootFrame.width,
      this.rootFrame.height,
      this.paneCount,
      this.topInset,
      this.bottomInset
    ) === FullPlayerLayoutMode.ULTRA_COMPACT;
  }

  private currentArtistLabel(): string {
    if (this.playerStore.currentTrack === undefined) {
      return '选择一首音乐开始播放';
    }
    return this.playerStore.currentTrack.artistDisplay.trim().length > 0 ?
      this.playerStore.currentTrack.artistDisplay : '未知艺术家';
  }

  private contentColor(): string {
    return this.primaryContentColor;
  }

  private secondaryContentColor(): string {
    return DynamicColor.withEmphasis(this.contentColor(), ForegroundEmphasis.MEDIUM);
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

  private headerTextInset(page: FullPlayerPage): number {
    if (this.isUltraCompact()) {
      return PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET;
    }
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
          PlayerImageIcon({
            source: $r('app.media.control_chevron_down'),
            iconSize: PlayerLayoutSpec.FULL_PLAYER_CLOSE_ICON_SIZE,
            contentColor: this.contentColor()
          })
        }
        .width(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        .borderRadius(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE / 2)
        .backgroundColor(Color.Transparent)
        .clickEffect({ level: ClickEffectLevel.LIGHT })
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
    FullPlayerQueueHeader({
      playerStore: this.playerStore,
      selectionStore: this.queueSelectionStore,
      selectionEnabled: AppShellLayoutSpec.supportsTitleSearchAndSelection(this.rootFrame.width),
      pageWidth: this.pageWidth(),
      leadingInset: this.headerTextInset(FullPlayerPage.QUEUE),
      primaryContentColor: this.contentColor(),
      secondaryContentColor: this.secondaryContentColor(),
      onRequestAddToPlaylist: this.onRequestAddToPlaylist
    })
  }

  @Builder
  private LyricsHeader() {
    Column({ space: 2 }) {
      if (this.paneCount === 1) {
        Text(this.playerStore.currentTrack?.title ?? '尚未播放')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.contentColor())
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          .maxLines(1)
        Text(this.currentArtistLabel())
          .fontSize(12)
          .fontColor(this.secondaryContentColor())
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
    FullPlayerQueuePage({
      playerStore: this.playerStore,
      libraryStore: this.libraryStore,
      selectionStore: this.queueSelectionStore,
      pageWidth: this.pageWidth(),
      paneCount: this.paneCount,
      bottomInset: this.bottomInset,
      listenerActive: !this.measuresArtworkTarget,
      pageScrollingEnabled: this.pageScrollingEnabled,
      focusAnimationEnabled: this.pageScrollingEnabled,
      primaryContentColor: this.contentColor(),
      secondaryContentColor: this.secondaryContentColor(),
      onPlayQueueTrack: this.onPlayQueueTrack,
      onResolveQueueArtwork: this.onResolveQueueArtwork,
      onOpenTrackDetails: this.onOpenTrackDetails,
      onNavigateLibrary: this.onNavigateLibrary,
      onRequestAddToPlaylist: this.onRequestAddToPlaylist
    })
  }

  @Builder
  private CoverPage() {
    FullPlayerCoverPage({
      playerStore: this.playerStore,
      ultraCompact: false,
      marqueeActive: this.marqueeActive,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      showArtwork: this.showArtwork,
      showPlaybackButton: this.showPlaybackButton,
      measuresArtworkTarget: this.measuresArtworkTarget,
      rootFrame: this.rootFrame,
      pagePosition: this.pagePosition,
      paneCount: this.paneCount,
      primaryContentColor: this.contentColor(),
      artworkSourceWidth: this.artworkSourceWidth,
      artworkSourceHeight: this.artworkSourceHeight,
      previousArtworkFrame: this.previousArtworkFrame,
      previousCenteredArtworkFrame: this.previousCenteredArtworkFrame,
      onClose: this.onClose,
      onNavigatePage: this.onNavigatePage,
      onSeek: this.onSeek,
      onOpenTrackActions: this.onOpenTrackActions,
      onOpenTrackDetails: this.onOpenTrackDetails,
      onRequestAddToPlaylist: this.onRequestAddToPlaylist,
      onCompletedCollectionChange: this.onCompletedCollectionChange,
      onArtworkTarget: this.onArtworkTarget,
      onCenteredArtworkTarget: this.onCenteredArtworkTarget,
      onPlaybackButtonTarget: this.onPlaybackButtonTarget
    })
  }

  @Builder
  private LyricsPage() {
    FullPlayerLyricsPage({
      playerStore: this.playerStore,
      pageWidth: this.pageWidth(),
      paneCount: this.paneCount,
      rootHeight: this.rootFrame.height,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      listenerActive: !this.measuresArtworkTarget,
      pageScrollingEnabled: this.pageScrollingEnabled,
      focusAnimationEnabled: this.pageScrollingEnabled,
      primaryContentColor: this.contentColor(),
      secondaryContentColor: this.secondaryContentColor(),
      onSeek: this.onSeek
    })
  }

  @Builder
  private UltraCompactCoverPage() {
    FullPlayerCoverPage({
      playerStore: this.playerStore,
      ultraCompact: true,
      marqueeActive: this.marqueeActive,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      showArtwork: this.showArtwork,
      showPlaybackButton: this.showPlaybackButton,
      measuresArtworkTarget: this.measuresArtworkTarget,
      rootFrame: this.rootFrame,
      pagePosition: this.pagePosition,
      paneCount: this.paneCount,
      primaryContentColor: this.contentColor(),
      artworkSourceWidth: this.artworkSourceWidth,
      artworkSourceHeight: this.artworkSourceHeight,
      previousArtworkFrame: this.previousArtworkFrame,
      previousCenteredArtworkFrame: this.previousCenteredArtworkFrame,
      onClose: this.onClose,
      onNavigatePage: this.onNavigatePage,
      onSeek: this.onSeek,
      onOpenTrackActions: this.onOpenTrackActions,
      onOpenTrackDetails: this.onOpenTrackDetails,
      onRequestAddToPlaylist: this.onRequestAddToPlaylist,
      onCompletedCollectionChange: this.onCompletedCollectionChange,
      onArtworkTarget: this.onArtworkTarget,
      onCenteredArtworkTarget: this.onCenteredArtworkTarget,
      onPlaybackButtonTarget: this.onPlaybackButtonTarget
    })
  }

  @Builder
  private UltraCompactQueueHeader() {
    Row({ space: 8 }) {
      Text('当前播放队列')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.contentColor())
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(`${this.playerStore.queueSize} 首`)
        .fontSize(13)
        .fontColor(this.secondaryContentColor())
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
    }
    .width(this.pageWidth())
    .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
    .padding({
      left: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET
    })
  }

  @Builder
  private UltraCompactQueuePage() {
    Column() {
      this.UltraCompactQueueHeader()
      Stack() {
        this.QueuePage()
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width(this.pageWidth())
    .height('100%')
    .padding({
      top: this.topInset + PlayerLayoutSpec.ULTRA_COMPACT_VERTICAL_INSET
    })
  }

  @Builder
  private UltraCompactLyricsPage() {
    Column() {
      this.LyricsHeader()
      Stack() {
        this.LyricsPage()
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width(this.pageWidth())
    .height('100%')
    .padding({
      top: this.topInset + PlayerLayoutSpec.ULTRA_COMPACT_VERTICAL_INSET
    })
  }

  @Builder
  private PlayerPages() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 0 }) {
        if (this.shouldRenderPage(FullPlayerPage.QUEUE)) {
          if (this.isUltraCompact()) {
            this.UltraCompactQueuePage()
          } else {
            this.QueuePage()
          }
        } else {
          Stack().width(this.pageWidth()).height('100%')
        }
        if (this.isUltraCompact()) {
          this.UltraCompactCoverPage()
        } else {
          this.CoverPage()
        }
        if (this.shouldRenderPage(FullPlayerPage.LYRICS)) {
          if (this.isUltraCompact()) {
            this.UltraCompactLyricsPage()
          } else {
            this.LyricsPage()
          }
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
    if (this.isUltraCompact()) {
      this.PlayerPages()
    } else if (this.measuresArtworkTarget) {
      if (this.paneCount > 1) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.CoverPage()
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.topInset })
      } else {
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
        .padding({ top: this.topInset })
      }
    } else if (this.paneCount > 1) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.PlayerPages()
        this.Header()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topInset })
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
      .padding({ top: this.topInset })
    }
  }
}
