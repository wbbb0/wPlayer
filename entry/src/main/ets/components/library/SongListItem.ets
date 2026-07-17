import { TrackListItem } from '../../library/model/LibraryModels';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { QueueActionMenu } from './QueueActionMenu';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';

export interface SongListItemData {
  id: number;
  title: string;
  artistDisplay: string;
  durationMs: number;
  artworkWidth: number;
  artworkHeight: number;
}

export enum SongListItemLayout {
  LIBRARY,
  ALBUM,
  PLAYER_QUEUE
}

@Component
export struct SongListItem {
  @Prop item: SongListItemData;
  @Prop layout: SongListItemLayout = SongListItemLayout.LIBRARY;
  @Prop artworkPath: string = '';
  @Prop trackNumber: number = 0;
  @Prop queueIndex: number = -1;
  @Prop currentQueueIndex: number = -1;
  @Prop showArtist: boolean = true;
  @Prop actionTrack: TrackListItem | undefined = undefined;
  @Prop menuPlacement: Placement = Placement.Bottom;
  @Prop primaryColor: ResourceColor = $r('app.color.text_primary');
  @Prop secondaryColor: ResourceColor = $r('app.color.text_secondary');
  @Prop tertiaryColor: ResourceColor = $r('app.color.text_tertiary');
  @Prop animateColors: boolean = false;
  @Prop active: boolean = false;
  @Prop activeBackgroundColor: ResourceColor = Color.Transparent;
  @Prop activeShadowColor: ResourceColor = Color.Transparent;
  @Prop activeShadowRadius: number = 0;
  @Prop activeShadowOffsetY: number = 0;
  @Prop horizontalInset: number = 16;
  @Prop verticalInset: number = 8;
  @Prop minimumHeight: number = 0;
  @Prop rowCornerRadius: number = 0;
  @Prop artworkSize: number = 52;
  @Prop artworkCornerRadius: number = 10;
  @Prop queueIndexWidth: number = 28;
  @Prop queueGestureDistance: number = 8;
  onActivate: () => void = (): void => {};

  private durationLabel(): string {
    const totalSeconds = Math.max(0, Math.floor(this.item.durationMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private artistLabel(): string {
    return this.item.artistDisplay.trim().length > 0 ? this.item.artistDisplay : '未知艺术家';
  }

  private rowSpace(): number {
    return this.layout === SongListItemLayout.PLAYER_QUEUE ? 10 : 12;
  }

  private textSpace(): number {
    return this.layout === SongListItemLayout.LIBRARY ? 4 : 3;
  }

  private titleSize(): number {
    return this.layout === SongListItemLayout.ALBUM ? 15 : 16;
  }

  private secondarySize(): number {
    return this.layout === SongListItemLayout.ALBUM ? 12 : 13;
  }

  private durationSize(): number {
    return this.layout === SongListItemLayout.PLAYER_QUEUE ? 13 : 12;
  }

  private queuePositionLabel(): string {
    if (this.queueIndex <= this.currentQueueIndex) {
      return '';
    }
    return `${this.queueIndex - this.currentQueueIndex}`;
  }

  private menuItems(): Array<TrackListItem> {
    return this.actionTrack === undefined ? [] : [this.actionTrack];
  }

  @Builder
  private QueuePosition() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.queueIndex === this.currentQueueIndex) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([this.primaryColor])
          .animation({
            duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
            curve: Curve.EaseInOut
          })
      } else {
        Text(this.queuePositionLabel())
          .fontSize(12)
          .fontColor(this.secondaryColor)
          .animation({
            duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
            curve: Curve.EaseInOut
          })
          .textAlign(TextAlign.Center)
      }
    }
    .width(this.queueIndexWidth)
    .height(this.artworkSize)
  }

  @Builder
  private LeadingContent() {
    if (this.layout === SongListItemLayout.ALBUM) {
      Text(this.trackNumber > 0 ? `${this.trackNumber}` : '—')
        .width(this.queueIndexWidth)
        .fontSize(13)
        .fontColor(this.tertiaryColor)
        .animation({
          duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
          curve: Curve.EaseInOut
        })
        .textAlign(TextAlign.End)
    } else {
      if (this.layout === SongListItemLayout.PLAYER_QUEUE) {
        this.QueuePosition()
      }
      ArtworkView({
        sourcePath: this.artworkPath,
        sourceWidth: this.item.artworkWidth,
        sourceHeight: this.item.artworkHeight,
        slotWidth: this.artworkSize,
        fitMode: ArtworkFitMode.CONTAIN,
        cornerRadius: this.artworkCornerRadius
      })
    }
  }

  @Builder
  private RowContent() {
    this.LeadingContent()

    Column({ space: this.textSpace() }) {
      Text(this.item.title)
        .fontSize(this.titleSize())
        .fontWeight(this.active ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.primaryColor)
        .animation({
          duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
          curve: Curve.EaseInOut
        })
        .maxLines(1)
      if (this.showArtist) {
        Text(this.artistLabel())
          .fontSize(this.secondarySize())
          .fontColor(this.secondaryColor)
          .animation({
            duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
            curve: Curve.EaseInOut
          })
          .maxLines(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)

    Text(this.durationLabel())
      .fontSize(this.durationSize())
      .fontColor(this.tertiaryColor)
      .animation({
        duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
        curve: Curve.EaseInOut
      })

    if (this.actionTrack !== undefined) {
      Button() {
        Image($r('app.media.control_more'))
          .width(18)
          .height(18)
          .fillColor(this.primaryColor)
          .animation({
            duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
            curve: Curve.EaseInOut
          })
      }
      .width(38)
      .height(38)
      .borderRadius(19)
      .backgroundColor(Color.Transparent)
      .accessibilityText('更多歌曲操作')
      .bindMenu(QueueActionMenu(this.menuItems()), { placement: this.menuPlacement })
    }
  }

  @Builder
  private StandardRow() {
    Row({ space: this.rowSpace() }) {
      this.RowContent()
    }
    .width('100%')
    .constraintSize({ minHeight: this.minimumHeight })
    .padding({
      left: this.horizontalInset,
      right: this.horizontalInset,
      top: this.verticalInset,
      bottom: this.verticalInset
    })
    .borderRadius(this.rowCornerRadius)
    .hoverEffect(HoverEffect.None)
    .onClick(() => {
      this.onActivate();
    })
  }

  @Builder
  private PlayerQueueRow() {
    Row({ space: this.rowSpace() }) {
      this.RowContent()
    }
    .width('100%')
    .constraintSize({ minHeight: this.minimumHeight })
    .padding({
      left: this.horizontalInset,
      right: this.horizontalInset,
      top: this.verticalInset,
      bottom: this.verticalInset
    })
    .borderRadius(this.rowCornerRadius)
    .backgroundColor(this.active ? this.activeBackgroundColor : Color.Transparent)
    .shadow(this.active ? {
      radius: this.activeShadowRadius,
      color: this.activeShadowColor,
      offsetY: this.activeShadowOffsetY
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
          distance: this.queueGestureDistance
        }),
        TapGesture().onAction(() => {
          this.onActivate();
        })
      )
    )
  }

  build() {
    if (this.layout === SongListItemLayout.PLAYER_QUEUE) {
      this.PlayerQueueRow()
    } else {
      this.StandardRow()
    }
  }
}
