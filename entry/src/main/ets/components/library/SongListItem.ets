import {
  LibraryEntityIdentity,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { TrackContextMenu } from './TrackActionMenu';
import { AvailabilityState } from '../../library/model/LibraryModels';
import { LibraryItemAvailability } from './LibraryItemAvailability';

export class SongListItemLayoutSpec {
  static readonly CONTEXT_PREVIEW_FALLBACK_WIDTH: number = 344;
  static readonly LIBRARY_PREVIEW_TRAILING_RESERVE: number = 132;
}

export interface SongListItemData {
  id: number;
  title: string;
  artistDisplay: string;
  durationMs: number;
  artworkWidth: number;
  artworkHeight: number;
  availability?: AvailabilityState;
}

export enum SongListItemLayout {
  LIBRARY,
  ALBUM,
  PLAYER_QUEUE
}

@Reusable
@Component
export struct SongListItem {
  @State contextMenuShown: boolean = false;
  @Prop item: SongListItemData;
  @Prop layout: SongListItemLayout = SongListItemLayout.LIBRARY;
  @Prop artworkPath: string = '';
  @Prop trackNumber: number = 0;
  @Prop queueIndex: number = -1;
  @Prop currentQueueIndex: number = -1;
  @Prop showArtist: boolean = true;
  @Prop libraryStore: LibraryStore | undefined = undefined;
  @Prop currentIdentity: LibraryEntityIdentity | undefined = undefined;
  @Prop actionTrack: TrackListItem | undefined = undefined;
  @Prop removeActionLabel: string = '';
  @Prop actionAnchorPrefix: string = 'library';
  @Prop menuPlacement: Placement = Placement.Right;
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
  @Prop contextPreviewWidth: number = SongListItemLayoutSpec.CONTEXT_PREVIEW_FALLBACK_WIDTH;
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  onActivate: () => void = (): void => {};
  onToggleSelection: () => void = (): void => {};
  onOpenActions: (track: TrackListItem, anchorId: string) => void =
    (_track: TrackListItem, _anchorId: string): void => {};
  onNavigateAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onRemoveAction: (() => void) | undefined = undefined;
  private suppressActivationUntil: number = 0;

  aboutToReuse(params: ESObject): void {
    this.contextMenuShown = false;
    this.suppressActivationUntil = 0;
    this.onActivate = params.onActivate as () => void;
    this.onToggleSelection = params.onToggleSelection as () => void;
    this.onOpenActions = params.onOpenActions as (track: TrackListItem, anchorId: string) => void;
    this.onNavigateAction = params.onNavigateAction as (target: LibraryNavigationTarget) => void;
    this.onRequestAddToPlaylist =
      params.onRequestAddToPlaylist as (items: Array<TrackListItem>) => void;
    this.onRemoveAction = params.onRemoveAction as (() => void) | undefined;
  }

  private durationLabel(): string {
    const totalSeconds = Math.max(0, Math.floor(this.item.durationMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private artistLabel(): string {
    const unavailableLabel = LibraryItemAvailability.label(this.item.availability);
    if (unavailableLabel.length > 0) {
      return unavailableLabel;
    }
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

  private actionAnchorId(): string {
    return `track_more_${this.actionAnchorPrefix}_${this.item.id}`;
  }

  private effectiveContextPreviewWidth(): number {
    return Math.max(
      SongListItemLayoutSpec.CONTEXT_PREVIEW_FALLBACK_WIDTH,
      this.contextPreviewWidth
    );
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
  private IdentityContent() {
    Row({ space: this.rowSpace() }) {
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
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.showArtist) {
          Text(this.artistLabel())
            .fontSize(this.secondarySize())
            .fontColor(this.secondaryColor)
            .animation({
              duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
              curve: Curve.EaseInOut
            })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .clip(true)
    }
    .width('100%')
    .clip(true)
  }

  @Builder
  private TrailingContent() {
    if (LibraryItemAvailability.unavailable(this.item.availability)) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(17)
        .fontColor([$r('app.color.text_tertiary')])
    }
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
      .id(this.actionAnchorId())
      .onClick(() => {
        if (this.actionTrack !== undefined) {
          this.onOpenActions(this.actionTrack, this.actionAnchorId());
        }
      })
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
      if (this.selectionMode) {
        this.onToggleSelection();
      } else {
        this.onActivate();
      }
    })
  }

  @Builder
  private ContextMenu() {
    if (this.libraryStore !== undefined && this.actionTrack !== undefined) {
      TrackContextMenu({
        store: this.libraryStore,
        track: this.actionTrack,
        current: this.currentIdentity,
        onNavigate: this.onNavigateAction,
        onRequestAddToPlaylist: this.onRequestAddToPlaylist,
        removeLabel: this.removeActionLabel,
        onRemove: this.onRemoveAction
      })
    }
  }

  @Builder
  private RowContent() {
    Stack() {
      SymbolGlyph(this.selected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(22)
        .fontColor([this.selected ? $r('app.color.theme_accent') : this.tertiaryColor])
    }
    .width(this.selectionMode ? 30 : 0)
    .opacity(this.selectionMode ? 1 : 0)
    .translate({ x: this.selectionMode ? 0 : -12 })
    .margin({ right: this.selectionMode ? 8 : 0 })
    .clip(true)
    .animation({ duration: 180, curve: Curve.EaseOut })
    Row() {
      this.IdentityContent()
    }
    .layoutWeight(1)
    .clip(true)

    this.TrailingContent()
  }

  @Builder
  private ContextMenuPreview() {
    Row({ space: this.rowSpace() }) {
      this.LeadingContent()

      Column({ space: this.textSpace() }) {
        Text(this.item.title)
          .fontSize(this.titleSize())
          .fontWeight(this.active ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.primaryColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.showArtist) {
          Text(this.artistLabel())
            .fontSize(this.secondarySize())
            .fontColor(this.secondaryColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
      .clip(true)
    }
    .width(this.effectiveContextPreviewWidth())
    .clip(true)
  }

  @Builder
  private ContextMenuIdentity() {
    Row() {
      this.IdentityContent()
    }
    .width('100%')
    .clip(true)
    .opacity(this.contextMenuShown ? 0 : 1)
    .bindContextMenu(
      this.contextMenuShown,
      this.ContextMenu(),
      {
        preview: this.ContextMenuPreview,
        placement: this.menuPlacement,
        previewBorderRadius: 0,
        layoutRegionMargin: { left: 16, right: 16 },
        onDisappear: (): void => {
          this.contextMenuShown = false;
        }
      }
    )
  }

  @Builder
  private StandardRowWithContextMenu() {
    if (this.selectionMode) {
      this.StandardRow()
    } else {
    Row({ space: this.rowSpace() }) {
      Row() {
        this.ContextMenuIdentity()
      }
      .layoutWeight(1)
      .clip(true)

      this.TrailingContent()
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
      if (Date.now() < this.suppressActivationUntil) {
        return;
      }
      this.onActivate();
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.suppressActivationUntil = Date.now() + 800;
          this.contextMenuShown = true;
        })
    )
    }
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
          if (this.selectionMode) {
            this.onToggleSelection();
          } else {
            this.onActivate();
          }
        })
      )
    )
  }

  build() {
    Column() {
      if (this.layout === SongListItemLayout.PLAYER_QUEUE) {
        this.PlayerQueueRow()
      } else if (this.actionTrack !== undefined && this.libraryStore !== undefined) {
        this.StandardRowWithContextMenu()
      } else {
        this.StandardRow()
      }
    }
    .width('100%')
    .opacity(LibraryItemAvailability.opacity(this.item.availability))
  }
}
