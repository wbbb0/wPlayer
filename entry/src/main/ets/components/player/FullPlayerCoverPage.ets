import {
  FullPlayerPage,
  FullPlayerPagerSpec,
  PlayerFrame,
  PlayerLayoutSpec
} from './PlayerMotion';
import {
  PlayerImageIcon,
  PlayerPlaybackButton,
  PlayerSymbolIcon,
  PlayerTransportAction,
  PlayerTransportButton
} from './PlayerControls';
import { PlayerHeroArtwork } from './PlayerArtworkViews';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import {
  CurrentTrackActionMenu,
  CurrentTrackActionMenuParams
} from './PlayerActionMenus';
import { LayoutLength } from '../layout/LayoutLength';
import { ArtworkLayout, ArtworkSize } from '../artwork/ArtworkLayout';
import { DynamicColor, ForegroundEmphasis } from '../../appearance/DynamicColor';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerTrackMarquee } from './PlayerTrackMarquee';
import { TrackListItem } from '../../library/model/LibraryModels';
import { PlayerProgressControl } from './FullPlayerSharedControls';
import { queueTrackListItem } from './FullPlayerQueuePage';

@Component
export struct FullPlayerCoverPage {
  @ObjectLink playerStore: PlayerStore;
  @Prop ultraCompact: boolean = false;
  @Prop marqueeActive: boolean = true;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop showArtwork: boolean = true;
  @Prop showPlaybackButton: boolean = true;
  @Prop measuresArtworkTarget: boolean = false;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop pagePosition: number = FullPlayerPage.COVER;
  @Prop paneCount: number = 1;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop showFloatingWindowButton: boolean = true;
  @Prop artworkSourceWidth: number = 0;
  @Prop artworkSourceHeight: number = 0;
  onNavigatePage: (page: FullPlayerPage) => void = (_page: FullPlayerPage): void => {};
  onClose: () => void = (): void => {};
  onSeek: (positionMs: number) => void = (_positionMs: number): void => {};
  onOpenTrackActions: (trackId: number, anchorId: string) => void =
    (_trackId: number, _anchorId: string): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};
  onCompletedCollectionChange: (enabled: boolean) => void =
    (_enabled: boolean): void => {};
  onOpenPlayerPageSettings: () => void = (): void => {};
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
  @State private artworkAvailableWidth: number = 0;
  @State private artworkAvailableHeight: number = 0;
  onArtworkTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};
  onCenteredArtworkTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};
  onPlaybackButtonTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};

  @Builder
  private CurrentTrackMenu() {
    CurrentTrackActionMenu(new CurrentTrackActionMenuParams({
      trackAvailable: this.playerStore.currentTrack !== undefined,
      completedCollectionEnabled: this.playerStore.completedCollectionEnabled,
      onInsertNext: (): void => playbackRuntime.insertCurrentNext(),
      onAppendToQueue: (): void => playbackRuntime.appendCurrentToQueue(),
      onAddToPlaylist: (): void => {
        if (this.playerStore.currentTrack !== undefined) {
          this.onRequestAddToPlaylist([this.playerStore.currentTrack.id]);
        }
      },
      onOpenDetails: (): void => {
        if (this.playerStore.currentTrack !== undefined) {
          this.onOpenTrackDetails(queueTrackListItem(this.playerStore.currentTrack));
        }
      },
      onShareFile: (): void => {
        if (this.playerStore.currentTrack !== undefined) {
          this.onShareTrackFile(this.playerStore.currentTrack.id);
        }
      },
      onCompletedCollectionChange: this.onCompletedCollectionChange,
      onOpenPlayerPageSettings: this.onOpenPlayerPageSettings
    }))
  }

  private pageWidth(): number {
    return FullPlayerPagerSpec.pageSpan(this.rootFrame.width, this.paneCount);
  }

  private fallbackArtworkSlotSize(): number {
    return PlayerLayoutSpec.fullArtworkSize(
      this.rootFrame.width,
      this.rootFrame.height,
      this.topInset,
      this.bottomInset,
      this.paneCount
    );
  }

  private artworkSize(): ArtworkSize {
    const fallback = this.fallbackArtworkSlotSize();
    return ArtworkLayout.containedSizeWithSquareFallback(
      this.artworkSourceWidth > 0 ?
        this.artworkSourceWidth : this.playerStore.currentTrack?.artworkWidth ?? 0,
      this.artworkSourceHeight > 0 ?
        this.artworkSourceHeight : this.playerStore.currentTrack?.artworkHeight ?? 0,
      this.artworkAvailableWidth > 0 ? this.artworkAvailableWidth : fallback,
      this.artworkAvailableHeight > 0 ? this.artworkAvailableHeight : fallback
    );
  }

  private artworkWidth(): number {
    return this.artworkSize().width;
  }

  private artworkHeight(): number {
    return this.artworkSize().height;
  }

  private recordArtworkAvailableArea(newValue: Area): void {
    const width = LayoutLength.toNumber(newValue.width, this.artworkAvailableWidth);
    const height = LayoutLength.toNumber(newValue.height, this.artworkAvailableHeight);
    if (width > 0 && Math.abs(width - this.artworkAvailableWidth) >= 0.5) {
      this.artworkAvailableWidth = width;
    }
    if (height > 0 && Math.abs(height - this.artworkAvailableHeight) >= 0.5) {
      this.artworkAvailableHeight = height;
    }
  }

  private recordArtworkTarget(newValue: Area): void {
    if (!this.measuresArtworkTarget) {
      return;
    }
    const pageWidth = this.pageWidth();
    const size = this.artworkSize();
    const layoutTarget: PlayerFrame = {
      x: LayoutLength.toNumber(
        newValue.globalPosition.x,
        this.previousCenteredArtworkFrame.x + this.rootFrame.x
      ) - this.rootFrame.x,
      y: LayoutLength.toNumber(
        newValue.globalPosition.y,
        this.previousArtworkFrame.y + this.rootFrame.y
      ) - this.rootFrame.y,
      width: LayoutLength.toNumber(newValue.width, size.width),
      height: LayoutLength.toNumber(newValue.height, size.height)
    };
    const centeredTarget: PlayerFrame = {
      x: this.ultraCompact ?
        FullPlayerPagerSpec.centeredArtworkTargetX(layoutTarget.x, pageWidth) :
        layoutTarget.x,
      y: layoutTarget.y,
      width: layoutTarget.width,
      height: layoutTarget.height
    };
    this.onCenteredArtworkTarget(centeredTarget);
    this.onArtworkTarget({
      x: this.ultraCompact ?
        FullPlayerPagerSpec.artworkTargetX(layoutTarget.x, this.pagePosition, pageWidth) :
        FullPlayerPagerSpec.pagerArtworkTargetX(
          centeredTarget.x,
          this.pagePosition,
          pageWidth
        ),
      y: centeredTarget.y,
      width: centeredTarget.width,
      height: centeredTarget.height
    });
  }

  private recordPlaybackButtonTarget(newValue: Area, fallbackSize: number): void {
    if (!this.measuresArtworkTarget) {
      return;
    }
    const layoutX = LayoutLength.toNumber(newValue.globalPosition.x, this.rootFrame.x) -
      this.rootFrame.x;
    this.onPlaybackButtonTarget({
      x: this.ultraCompact ?
        FullPlayerPagerSpec.artworkTargetX(layoutX, this.pagePosition, this.pageWidth()) :
        layoutX,
      y: LayoutLength.toNumber(newValue.globalPosition.y, this.rootFrame.y) - this.rootFrame.y,
      width: LayoutLength.toNumber(newValue.width, fallbackSize),
      height: LayoutLength.toNumber(newValue.height, fallbackSize)
    });
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
    return this.primaryContentColor;
  }

  private secondaryContentColor(): string {
    return DynamicColor.withEmphasis(this.contentColor(), ForegroundEmphasis.MEDIUM);
  }

  private pageButtonDisabled(page: FullPlayerPage): boolean {
    const currentPosition = Math.round(
      FullPlayerPagerSpec.clampPosition(this.pagePosition, this.paneCount)
    );
    return currentPosition === FullPlayerPagerSpec.positionForPage(page, this.paneCount);
  }

  private enterPictureInPicture(): void {
    playbackRuntime.enterPictureInPicture(this.getUIContext())
      .then((closePlayerPage: boolean): void => {
        if (closePlayerPage) {
          this.onClose();
        }
      })
      .catch((error: Object): void => {
        const message = error instanceof Error ? error.message : '无法启动画中画';
        this.getUIContext().getPromptAction().showToast({ message: message });
      });
  }

  @Builder
  private PictureInPictureButton() {
    Stack() {
      PlayerImageIcon({
        source: $r('app.media.control_picture_in_picture'),
        iconSize: 20,
        contentColor: this.contentColor(),
        animateColor: false
      })
    }
    .width(40)
    .height(40)
    .borderRadius(20)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .enabled(this.playerStore.currentTrack !== undefined)
    .opacity(this.playerStore.currentTrack === undefined ? 0.38 : 1)
    .accessibilityText('显示专辑封面画中画')
    .onClick((): void => this.enterPictureInPicture())
  }

  @Builder
  private PageNavigationButton(page: FullPlayerPage) {
    Stack() {
      PlayerSymbolIcon({
        symbol: page === FullPlayerPage.QUEUE ?
          $r('sys.symbol.music_note_list_fill') : $r('sys.symbol.lyrics_square'),
        iconSize: 22,
        contentColor: this.contentColor(),
        animateColor: false
      })
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .enabled(!this.pageButtonDisabled(page))
    .opacity(this.pageButtonDisabled(page) ? 0.38 : 1)
    .accessibilityText(page === FullPlayerPage.QUEUE ? '打开播放队列' : '打开歌词')
    .onClick(() => {
      this.onNavigatePage(page);
    })
  }

  @Builder
  private PlayerArtwork() {
    Stack() {
      if (this.showArtwork) {
        PlayerHeroArtwork({
          playerStore: this.playerStore,
          artworkWidth: this.artworkWidth(),
          artworkHeight: this.artworkHeight(),
          cornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
          interpolation: ImageInterpolation.Medium
        })
      }
    }
    .width(this.artworkWidth())
    .height(this.artworkHeight())
    .borderRadius(Math.min(this.artworkWidth(), this.artworkHeight()) / 2)
    .accessibilityText('歌曲封面，长按打开更多操作')
    .onAreaChange((_oldValue: Area, newValue: Area) => this.recordArtworkTarget(newValue))
  }

  @Builder
  private PlayerArtworkSlot() {
    Stack({ alignContent: Alignment.Center }) {
      this.PlayerArtwork()
    }
    .width('100%')
    .layoutWeight(1)
    .onAreaChange((_oldValue: Area, newValue: Area) =>
      this.recordArtworkAvailableArea(newValue))
  }

  @Builder
  private StandardPage() {
    Column() {
      if (this.paneCount > 1) {
        Stack().height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
      }
      this.PlayerArtworkSlot()

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
              animateColor: false,
              titleSize: PlayerLayoutSpec.FULL_PLAYER_TITLE_SIZE,
              titleWeight: FontWeight.Bold
            })
              .layoutWeight(1)
          }

          if (this.showFloatingWindowButton) {
            this.PictureInPictureButton()
          }

          Stack() {
            PlayerImageIcon({
              source: $r('app.media.control_more'),
              iconSize: 20,
              contentColor: this.contentColor(),
              animateColor: false
            })
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .clickEffect({ level: ClickEffectLevel.MIDDLE })
          .accessibilityText('更多操作')
          .bindMenu(this.CurrentTrackMenu(), { placement: Placement.BottomRight })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.measuresArtworkTarget) {
          Text(this.currentArtistLabel())
            .fontSize(PlayerLayoutSpec.FULL_PLAYER_ARTIST_SIZE)
            .fontColor(this.secondaryContentColor())
            .maxLines(1)
        } else {
          Text(this.currentArtistLabel())
            .fontSize(PlayerLayoutSpec.FULL_PLAYER_ARTIST_SIZE)
            .fontColor(this.secondaryContentColor())
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
      .margin({ top: PlayerLayoutSpec.FULL_PLAYER_ARTWORK_METADATA_GAP })

      PlayerProgressControl({
        playerStore: this.playerStore,
        progressStore: this.playerStore.progress,
        primaryContentColor: this.contentColor(),
        secondaryContentColor: this.secondaryContentColor(),
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
          PlayerTransportButton({
            playerStore: this.playerStore,
            action: PlayerTransportAction.PREVIOUS,
            buttonSize: 52,
            contentColor: this.contentColor(),
            iconAnimationEnabled: false
          })
          PlayerPlaybackButton({
            playerStore: this.playerStore,
            buttonSize: PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE,
            iconSize: PlayerLayoutSpec.FULL_PLAYBACK_ICON_SIZE,
            contentColor: this.contentColor(),
            iconAnimationEnabled: false
          })
            .opacity(this.showPlaybackButton ? 1 : 0)
            .enabled(this.showPlaybackButton)
            .onAreaChange((_oldValue: Area, newValue: Area) => {
              this.recordPlaybackButtonTarget(
                newValue,
                PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE
              );
            })
        PlayerTransportButton({
            playerStore: this.playerStore,
            action: PlayerTransportAction.NEXT,
            buttonSize: 52,
          contentColor: this.contentColor(),
          iconAnimationEnabled: false
          })
        }
        .align(Alignment.Center)
      }
      .height(PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE)
      .width('100%')
      .margin({ top: 18, bottom: 12 })
    }
    .width(this.pageWidth())
    .height('100%')
    .padding({
      left: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET,
      bottom: this.bottomInset
    })
  }

  @Builder
  private UltraCompactMetadata() {
    Row({ space: 8 }) {
      Column({ space: 4 }) {
        if (this.measuresArtworkTarget) {
          Text(this.currentTitleLabel())
            .fontSize(PlayerLayoutSpec.FULL_PLAYER_TITLE_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.contentColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          PlayerTrackMarquee({
            playerStore: this.playerStore,
            active: this.marqueeActive,
            titleColor: this.contentColor(),
            animateColor: false,
            titleSize: PlayerLayoutSpec.FULL_PLAYER_TITLE_SIZE,
            titleWeight: FontWeight.Bold
          })
        }
        Text(this.currentArtistLabel())
          .fontSize(PlayerLayoutSpec.FULL_PLAYER_ARTIST_SIZE)
          .fontColor(this.secondaryContentColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .id('ultra_compact_player_artist_action')
          .accessibilityText('查看艺术家、专辑艺术家或专辑')
          .onClick(() => {
            if (!this.measuresArtworkTarget && this.playerStore.currentTrack !== undefined) {
              this.onOpenTrackActions(
                this.playerStore.currentTrack.id,
                'ultra_compact_player_artist_action'
              );
            }
          })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.measuresArtworkTarget && this.showFloatingWindowButton) {
        this.PictureInPictureButton()
      }
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.End)
    .width('100%')
    .height(PlayerLayoutSpec.ULTRA_COMPACT_TEXT_HEIGHT)
    .padding({ right: PlayerLayoutSpec.ULTRA_COMPACT_CONTROL_RAIL_WIDTH })
  }

  @Builder
  private UltraCompactControls() {
    Column({ space: PlayerLayoutSpec.ULTRA_COMPACT_CONTROL_GAP }) {
      PlayerTransportButton({
        playerStore: this.playerStore,
        action: PlayerTransportAction.PREVIOUS,
        buttonSize: PlayerLayoutSpec.ULTRA_COMPACT_TRANSPORT_BUTTON_SIZE,
        contentColor: this.contentColor(),
        iconAnimationEnabled: false
      })
      PlayerPlaybackButton({
        playerStore: this.playerStore,
        buttonSize: PlayerLayoutSpec.ULTRA_COMPACT_PLAYBACK_BUTTON_SIZE,
        iconSize: PlayerLayoutSpec.ULTRA_COMPACT_PLAYBACK_ICON_SIZE,
        contentColor: this.contentColor(),
        iconAnimationEnabled: false
      })
        .opacity(this.showPlaybackButton ? 1 : 0)
        .enabled(this.showPlaybackButton)
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          this.recordPlaybackButtonTarget(
            newValue,
            PlayerLayoutSpec.ULTRA_COMPACT_PLAYBACK_BUTTON_SIZE
          );
        })
      PlayerTransportButton({
        playerStore: this.playerStore,
        action: PlayerTransportAction.NEXT,
        buttonSize: PlayerLayoutSpec.ULTRA_COMPACT_TRANSPORT_BUTTON_SIZE,
        contentColor: this.contentColor(),
        iconAnimationEnabled: false
      })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width(PlayerLayoutSpec.ULTRA_COMPACT_CONTROL_RAIL_WIDTH)
  }

  @Builder
  private UltraCompactPage() {
    Row({ space: PlayerLayoutSpec.ULTRA_COMPACT_COLUMN_GAP }) {
      Column({ space: PlayerLayoutSpec.ULTRA_COMPACT_TEXT_GAP }) {
        this.PlayerArtworkSlot()
        this.UltraCompactMetadata()
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(HorizontalAlign.Start)

      this.UltraCompactControls()
    }
    .width(this.pageWidth())
    .height('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: PlayerLayoutSpec.ULTRA_COMPACT_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.ULTRA_COMPACT_HORIZONTAL_INSET,
      top: this.topInset + PlayerLayoutSpec.ULTRA_COMPACT_VERTICAL_INSET,
      bottom: this.bottomInset + PlayerLayoutSpec.ULTRA_COMPACT_VERTICAL_INSET
    })
  }

  build() {
    if (this.ultraCompact) {
      this.UltraCompactPage()
    } else {
      this.StandardPage()
    }
  }
}
