import {
  FullPlayerPage,
  FullPlayerPagerSpec,
  PlayerFrame,
  PlayerLayoutSpec,
  PlayerPoint
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
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
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
  @Prop heroArtworkInterpolation: ImageInterpolation = ImageInterpolation.High;
  @Prop measuresArtworkTarget: boolean = false;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop pagePosition: number = FullPlayerPage.COVER;
  @Prop paneCount: number = 1;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop previousArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  @Prop previousCenteredArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  onNavigatePage: (page: FullPlayerPage) => void = (_page: FullPlayerPage): void => {};
  onSeek: (positionMs: number) => void = (_positionMs: number): void => {};
  onOpenTrackActions: (trackId: number, anchorId: string) => void =
    (_trackId: number, _anchorId: string): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};
  onCompletedCollectionChange: (enabled: boolean) => void =
    (_enabled: boolean): void => {};
  onArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  onCenteredArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  onPlaybackButtonTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};

  @Builder
  private CurrentTrackMenu() {
    CurrentTrackActionMenu(new CurrentTrackActionMenuParams(
      this.playerStore.currentTrack !== undefined,
      this.playerStore.completedCollectionEnabled,
      () => playbackRuntime.insertCurrentNext(),
      () => playbackRuntime.appendCurrentToQueue(),
      () => {
        if (this.playerStore.currentTrack !== undefined) {
          this.onRequestAddToPlaylist([this.playerStore.currentTrack.id]);
        }
      },
      () => {
        if (this.playerStore.currentTrack !== undefined) {
          this.onOpenTrackDetails(queueTrackListItem(this.playerStore.currentTrack));
        }
      },
      this.onCompletedCollectionChange
    ))
  }

  private pageWidth(): number {
    return FullPlayerPagerSpec.pageSpan(this.rootFrame.width, this.paneCount);
  }

  private artworkSlotSize(): number {
    return PlayerLayoutSpec.fullArtworkSize(
      this.rootFrame.width,
      this.rootFrame.height,
      this.topInset,
      this.bottomInset,
      this.paneCount
    );
  }

  private recordArtworkTarget(newValue: Area): void {
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
      x: this.ultraCompact ?
        FullPlayerPagerSpec.centeredArtworkTargetX(layoutTarget.x, pageWidth) :
        layoutTarget.x,
      y: layoutTarget.y
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
      y: centeredTarget.y
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

  @Builder
  private PageNavigationButton(page: FullPlayerPage) {
    Stack() {
      PlayerSymbolIcon({
        symbol: page === FullPlayerPage.QUEUE ?
          $r('sys.symbol.music_note_list_fill') : $r('sys.symbol.lyrics_square'),
        iconSize: 22,
        contentColor: this.contentColor()
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
          slotSize: this.artworkSlotSize(),
          cornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
          interpolation: this.heroArtworkInterpolation
        })
      }
    }
    .width(this.artworkSlotSize())
    .height(this.artworkSlotSize())
    .borderRadius(this.artworkSlotSize() / 2)
    .accessibilityText('歌曲封面，长按打开更多操作')
    .onAreaChange((_oldValue: Area, newValue: Area) => this.recordArtworkTarget(newValue))
  }

  @Builder
  private StandardPage() {
    Column() {
      Blank().layoutWeight(1)

      this.PlayerArtwork()

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
            PlayerImageIcon({
              source: $r('app.media.control_more'),
              iconSize: 20,
              contentColor: this.contentColor()
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
            contentColor: this.contentColor()
          })
          PlayerPlaybackButton({
            playerStore: this.playerStore,
            buttonSize: PlayerLayoutSpec.FULL_PLAYBACK_BUTTON_SIZE,
            contentColor: this.contentColor()
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
            contentColor: this.contentColor()
          })
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
  private UltraCompactMetadata() {
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
          titleSize: PlayerLayoutSpec.FULL_PLAYER_TITLE_SIZE,
          titleWeight: FontWeight.Bold,
          animateColor: true
        })
      }
      Text(this.currentArtistLabel())
        .fontSize(PlayerLayoutSpec.FULL_PLAYER_ARTIST_SIZE)
        .fontColor(this.secondaryContentColor())
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
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
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.End)
    .width('100%')
    .height(PlayerLayoutSpec.ULTRA_COMPACT_TEXT_HEIGHT)
  }

  @Builder
  private UltraCompactControls() {
    Column({ space: PlayerLayoutSpec.ULTRA_COMPACT_CONTROL_GAP }) {
      PlayerTransportButton({
        playerStore: this.playerStore,
        action: PlayerTransportAction.PREVIOUS,
        buttonSize: PlayerLayoutSpec.ULTRA_COMPACT_TRANSPORT_BUTTON_SIZE,
        contentColor: this.contentColor()
      })
      PlayerPlaybackButton({
        playerStore: this.playerStore,
        buttonSize: PlayerLayoutSpec.ULTRA_COMPACT_PLAYBACK_BUTTON_SIZE,
        contentColor: this.contentColor()
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
        contentColor: this.contentColor()
      })
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width(PlayerLayoutSpec.ULTRA_COMPACT_CONTROL_RAIL_WIDTH)
  }

  @Builder
  private UltraCompactPage() {
    Row({ space: PlayerLayoutSpec.ULTRA_COMPACT_COLUMN_GAP }) {
      Column() {
        this.PlayerArtwork()
        Blank().layoutWeight(1)
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
