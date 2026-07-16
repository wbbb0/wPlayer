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
import { PlayerStore, QueueTrack } from '../../playback/model/PlaybackModels';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';

function lengthToNumber(value: Length | undefined, fallback: number): number {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    const parsedValue = Number.parseFloat(value);
    return Number.isNaN(parsedValue) ? fallback : parsedValue;
  }
  return fallback;
}

@Component
export struct FullPlayerContent {
  @ObjectLink playerStore: PlayerStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop showArtwork: boolean = true;
  @Prop measuresArtworkTarget: boolean = false;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop pagePosition: number = FullPlayerPage.COVER;
  @Prop paneCount: number = 1;
  @Prop previousArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  @Prop previousCenteredArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  onClose: () => void = (): void => {};
  onPlayQueueTrack: (trackId: number) => void = (_trackId: number): void => {};
  onSeek: (positionMs: number) => void = (_positionMs: number): void => {};
  onResolveQueueArtwork: (relativePath: string) => string = (_relativePath: string): string => '';
  onArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  onCenteredArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  private readonly queueScroller: Scroller = new Scroller();
  private lastFocusedQueueIndex: number = -1;
  private hasFocusedQueue: boolean = false;
  @State private seeking: boolean = false;
  @State private seekPreviewMs: number = 0;

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
    return Math.max(0, Math.min(this.playerStore.positionMs, this.playerStore.durationMs));
  }

  private currentArtistLabel(): string {
    if (this.playerStore.currentTrack === undefined) {
      return '选择一首音乐开始播放';
    }
    return this.playerStore.currentTrack.artistDisplay.trim().length > 0 ?
      this.playerStore.currentTrack.artistDisplay : '未知艺术家';
  }

  private updateSeek(value: number, mode: SliderChangeMode): void {
    this.seekPreviewMs = Math.max(0, Math.min(value, this.playerStore.durationMs));
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.seeking = true;
      return;
    }
    this.seeking = false;
    this.onSeek(Math.round(this.seekPreviewMs));
  }

  onDidBuild(): void {
    if (this.measuresArtworkTarget || this.playerStore.queueCurrentIndex < 0 ||
      this.lastFocusedQueueIndex === this.playerStore.queueCurrentIndex) {
      return;
    }
    this.lastFocusedQueueIndex = this.playerStore.queueCurrentIndex;
    this.queueScroller.scrollToIndex(
      this.playerStore.queueCurrentIndex,
      this.hasFocusedQueue,
      ScrollAlign.CENTER
    );
    this.hasFocusedQueue = true;
  }

  private headerTextInset(page: FullPlayerPage): number {
    if (this.paneCount === 1 || page === FullPlayerPage.QUEUE) {
      return PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET +
        PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE + PlayerLayoutSpec.FULL_PLAYER_HEADER_TEXT_GAP;
    }
    return PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET;
  }

  private queuePositionLabel(index: number): string {
    if (index <= this.playerStore.queueCurrentIndex) {
      return '';
    }
    return `${index - this.playerStore.queueCurrentIndex}`;
  }

  @Builder
  private QueuePosition(index: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (index === this.playerStore.queueCurrentIndex) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([this.playerStore.themeOnPrimary()])
      } else {
        Text(this.queuePositionLabel(index))
          .fontSize(12)
          .fontColor(this.playerStore.themeOnPrimaryMedium())
          .textAlign(TextAlign.Center)
      }
    }
    .width(PlayerLayoutSpec.FULL_PLAYER_QUEUE_INDEX_WIDTH)
    .height(PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE)
  }

  @Builder
  private Header() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row({ space: 0 }) {
        this.QueueHeader()
        Stack().width(this.pageWidth()).height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        this.LyricsHeader()
      }
      .width(this.pageWidth() * FullPlayerPagerSpec.PAGE_COUNT)
      .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
      .translate({ x: -this.pagePosition * this.pageWidth() })

      Row() {
        Stack() {
          Image($r('app.media.control_chevron_down'))
            .width(PlayerLayoutSpec.FULL_PLAYER_CLOSE_ICON_SIZE)
            .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_ICON_SIZE)
            .fillColor(this.playerStore.themeOnPrimary())
        }
        .width(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
        .borderRadius(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE / 2)
        .backgroundColor($r('app.color.glass_surface_strong'))
        .backgroundBlurStyle(BlurStyle.Thin)
        .clickEffect({ level: ClickEffectLevel.MIDDLE })
        .accessibilityText('收起播放器')
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
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
    Row() {
      Text('当前播放队列')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.playerStore.themeOnPrimary())
      Blank()
      Text(`${this.playerStore.queueSize} 首`)
        .fontSize(13)
        .fontColor(this.playerStore.themeOnPrimaryMedium())
    }
    .width(this.pageWidth())
    .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
    .padding({
      left: this.headerTextInset(FullPlayerPage.QUEUE),
      right: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET
    })
  }

  @Builder
  private LyricsHeader() {
    Column({ space: 2 }) {
      Text(this.playerStore.currentTrack?.title ?? '尚未播放')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.playerStore.themeOnPrimary())
        .maxLines(1)
      Text(this.currentArtistLabel())
        .fontSize(12)
        .fontColor(this.playerStore.themeOnPrimaryMedium())
        .maxLines(1)
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
    Column() {
      if (this.playerStore.queueItems.length === 0) {
        Column({ space: 8 }) {
          Text('队列为空')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.playerStore.themeOnPrimary())
          Text('从音乐库选择歌曲后会显示在这里')
            .fontSize(14)
            .fontColor(this.playerStore.themeOnPrimaryMedium())
        }
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .width('100%')
      } else {
        List({ space: 0, scroller: this.queueScroller }) {
          LazyForEach(this.playerStore.queueDataSource, (item: QueueTrack, index: number) => {
            ListItem() {
              Column() {
                if (index > 0) {
                  Divider()
                    .color(this.playerStore.themeOnPrimaryMedium())
                    .opacity(PlayerLayoutSpec.FULL_PLAYER_QUEUE_DIVIDER_OPACITY)
                    .margin({
                      left: PlayerLayoutSpec.FULL_PLAYER_QUEUE_INDEX_WIDTH +
                        PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE + 20 +
                        PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
                      right: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET
                    })
                }
                Row({ space: 10 }) {
                  this.QueuePosition(index)

                  ArtworkView({
                    sourcePath: this.onResolveQueueArtwork(item.smallArtworkPath),
                    sourceWidth: item.artworkWidth,
                    sourceHeight: item.artworkHeight,
                    slotWidth: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE,
                    fitMode: ArtworkFitMode.CONTAIN,
                    cornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS
                  })

                  Column({ space: 3 }) {
                    Text(item.title)
                      .fontSize(16)
                      .fontWeight(item.id === this.playerStore.currentTrack?.id ?
                        FontWeight.Bold : FontWeight.Medium)
                      .fontColor(this.playerStore.themeOnPrimary())
                      .maxLines(1)
                    Text(item.artistDisplay || '未知艺术家')
                      .fontSize(13)
                      .fontColor(this.playerStore.themeOnPrimaryMedium())
                      .maxLines(1)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(this.durationLabel(item.durationMs))
                    .fontSize(13)
                    .fontColor(this.playerStore.themeOnPrimaryMedium())
                }
                .width('100%')
                .padding({
                  left: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
                  right: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
                  top: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ROW_VERTICAL_INSET,
                  bottom: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ROW_VERTICAL_INSET
                })
                .borderRadius(14)
                .backgroundColor(item.id === this.playerStore.currentTrack?.id ?
                  $r('app.color.glass_surface_strong') : Color.Transparent)
                .shadow(item.id === this.playerStore.currentTrack?.id ? {
                  radius: PlayerLayoutSpec.FULL_PLAYER_QUEUE_SHADOW_RADIUS,
                  color: $r('app.color.artwork_shadow'),
                  offsetY: PlayerLayoutSpec.FULL_PLAYER_QUEUE_SHADOW_OFFSET_Y
                } : {
                  radius: 0,
                  color: Color.Transparent,
                  offsetY: 0
                })
                .hoverEffect(HoverEffect.None)
                .gesture(
                  GestureGroup(GestureMode.Exclusive,
                    PanGesture({
                      direction: PanDirection.Horizontal,
                      distance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE
                    }),
                    TapGesture().onAction(() => {
                      this.onPlayQueueTrack(item.id);
                    })
                  )
                )
              }
              .width('100%')
              .padding({
                left: PlayerLayoutSpec.FULL_PLAYER_QUEUE_SHADOW_CLEARANCE,
                right: PlayerLayoutSpec.FULL_PLAYER_QUEUE_SHADOW_CLEARANCE
              })
            }
          }, (item: QueueTrack) => `${item.id}`)
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
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
    .padding({
      top: PlayerLayoutSpec.FULL_PLAYER_PAGE_TOP_INSET,
      bottom: this.bottomInset + PlayerLayoutSpec.FULL_PLAYER_BOTTOM_INSET
    })
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
            cornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS
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
          x: lengthToNumber(
            newValue.globalPosition.x,
            this.previousCenteredArtworkTarget.x + this.rootFrame.x
          ) - this.rootFrame.x,
          y: lengthToNumber(
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
          Text(this.playerStore.currentTrack?.title ?? '尚未播放')
            .fontSize(PlayerLayoutSpec.FULL_PLAYER_TITLE_SIZE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.playerStore.themeOnPrimary())
            .maxLines(1)
            .layoutWeight(1)

          Row({ space: 2 }) {
            PlayerModeButton({ playerStore: this.playerStore, action: PlayerModeAction.SHUFFLE })
            PlayerModeButton({ playerStore: this.playerStore, action: PlayerModeAction.REPEAT })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.currentArtistLabel())
          .fontSize(PlayerLayoutSpec.FULL_PLAYER_ARTIST_SIZE)
          .fontColor(this.playerStore.themeOnPrimaryMedium())
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      this.ProgressControl()

      Row({ space: 16 }) {
        PlayerTransportButton({ playerStore: this.playerStore,
          action: PlayerTransportAction.PREVIOUS, buttonSize: 52 })
        PlayerPlaybackButton({ playerStore: this.playerStore, buttonSize: 64 })
        PlayerTransportButton({ playerStore: this.playerStore,
          action: PlayerTransportAction.NEXT, buttonSize: 52 })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
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
  private ProgressControl() {
    Column({ space: 2 }) {
      Slider({
        value: this.displayedPositionMs(),
        min: 0,
        max: Math.max(1, this.playerStore.durationMs),
        step: 1000,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .selectedColor(this.playerStore.themeAccent())
        .trackColor(this.playerStore.themeOnPrimaryMedium())
        .blockColor(this.playerStore.themeAccent())
        .trackThickness(PlayerLayoutSpec.FULL_PLAYER_PROGRESS_TRACK_THICKNESS)
        .enabled(this.playerStore.durationMs > 0)
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
        Blank()
        Text(this.durationLabel(this.playerStore.durationMs))
          .fontSize(11)
          .fontColor(this.playerStore.themeOnPrimaryMedium())
      }
      .width('100%')
    }
    .width('100%')
    .margin({ top: 8 })
  }

  @Builder
  private LyricsPage() {
    Column() {
      Column({ space: 10 }) {
        Text('暂未找到歌词')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.playerStore.themeOnPrimary())
        Text('支持歌词后，这里会优先显示同目录下的同名 LRC 文件')
          .fontSize(14)
          .fontColor(this.playerStore.themeOnPrimaryMedium())
          .textAlign(TextAlign.Center)
      }
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .width('100%')
    }
    .width(this.pageWidth())
    .height('100%')
    .padding({
      left: PlayerLayoutSpec.FULL_PLAYER_LYRICS_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.FULL_PLAYER_LYRICS_HORIZONTAL_INSET,
      top: PlayerLayoutSpec.FULL_PLAYER_PAGE_TOP_INSET,
      bottom: this.bottomInset + PlayerLayoutSpec.FULL_PLAYER_BOTTOM_INSET
    })
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
    } else {
      Column() {
        this.Header()

        Stack({ alignContent: Alignment.TopStart }) {
          Row({ space: 0 }) {
            this.QueuePage()
            this.CoverPage()
            this.LyricsPage()
          }
          .width(this.pageWidth() * FullPlayerPagerSpec.PAGE_COUNT)
          .height('100%')
          .translate({ x: -this.pagePosition * this.pageWidth() })
        }
        .layoutWeight(1)
        .width('100%')
        .clip(true)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.topInset + PlayerLayoutSpec.FULL_PLAYER_TOP_INSET })
    }
  }
}
