import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import {
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { LayoutLength } from '../layout/LayoutLength';
import { LibraryContextInteraction } from '../library/LibraryContextInteraction';
import { LibraryItemAvailability } from '../library/LibraryItemAvailability';
import {
  TrackActionMenu,
  TrackActionMenuParams
} from '../library/TrackActionMenu';
import { LibraryTrackRowStyle } from '../library/LibraryTrackRow';
import {
  LibraryLinkAction,
  libraryLinkActions
} from '../navigation/LibraryNavigation';

@Reusable
@Component
export struct QueueTrackRow {
  @ObjectLink store: LibraryStore;
  @Prop track: TrackListItem;
  @Prop artworkPath: string = '';
  @Prop queueIndex: number = -1;
  @Prop currentQueueIndex: number = -1;
  @Prop primaryColor: ResourceColor = $r('app.color.text_primary');
  @Prop secondaryColor: ResourceColor = $r('app.color.text_secondary');
  @Prop tertiaryColor: ResourceColor = $r('app.color.text_tertiary');
  @Prop animateColors: boolean = false;
  @Prop active: boolean = false;
  @Prop activeBackgroundColor: ResourceColor = Color.Transparent;
  @Prop activeShadowColor: ResourceColor = Color.Transparent;
  @Prop activeShadowRadius: number = 0;
  @Prop activeShadowOffsetY: number = 0;
  @Prop horizontalInset: number = 0;
  @Prop verticalInset: number = 0;
  @Prop rowCornerRadius: number = 0;
  @Prop artworkSize: number = 48;
  @Prop artworkCornerRadius: number = 10;
  @Prop queueIndexWidth: number = 28;
  @Prop queueGestureDistance: number = 8;
  @Prop actionAnchorPrefix: string = 'player_queue';
  @Prop menuPlacement: Placement = Placement.BottomLeft;
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  onActivate: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onToggleSelection: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onNavigateAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  @State contextMenuShown: boolean = false;
  @State linkActions: Array<LibraryLinkAction> = [];
  private measuredIdentityWidth: number = 0;
  private suppressActivationUntil: number = 0;
  private contextMenuLoadEpoch: number = 0;

  aboutToReuse(params: ESObject): void {
    this.contextMenuLoadEpoch += 1;
    this.contextMenuShown = false;
    this.linkActions = [];
    this.measuredIdentityWidth = 0;
    this.suppressActivationUntil = 0;
    this.onActivate = params.onActivate as (track: TrackListItem) => void;
    this.onToggleSelection = params.onToggleSelection as (track: TrackListItem) => void;
    this.onNavigateAction =
      params.onNavigateAction as (target: LibraryNavigationTarget) => void;
    this.onRequestAddToPlaylist =
      params.onRequestAddToPlaylist as (items: Array<TrackListItem>) => void;
  }

  aboutToRecycle(): void {
    this.contextMenuLoadEpoch += 1;
  }

  private durationLabel(): string {
    const totalSeconds = Math.max(0, Math.floor(this.track.durationMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private artistLabel(): string {
    const unavailableLabel = LibraryItemAvailability.label(this.track.availability);
    if (unavailableLabel.length > 0) {
      return unavailableLabel;
    }
    return this.track.artistDisplay.trim().length > 0 ? this.track.artistDisplay : '未知艺术家';
  }

  private queuePositionLabel(): string {
    if (this.queueIndex <= this.currentQueueIndex) {
      return '';
    }
    return `${this.queueIndex - this.currentQueueIndex}`;
  }

  private contextPreviewAnchorId(): string {
    return `track_context_preview_${this.actionAnchorPrefix}_${this.track.id}`;
  }

  private effectiveContextPreviewWidth(): number {
    return this.measuredIdentityWidth > 0 ? this.measuredIdentityWidth :
      LibraryTrackRowStyle.CONTEXT_PREVIEW_FALLBACK_WIDTH;
  }

  private showContextMenu(): void {
    try {
      const uiContext = this.getUIContext();
      const info = uiContext.getComponentUtils().getRectangleById(this.contextPreviewAnchorId());
      const width = uiContext.px2vp(LayoutLength.toNumber(info.size.width, 0));
      if (width > 0) {
        this.measuredIdentityWidth = width;
      }
    } catch (error) {
      console.warn(`Unable to measure queue context preview: ${error}`);
    }
    this.suppressActivationUntil =
      Date.now() + LibraryContextInteraction.ACTIVATION_SUPPRESSION_DURATION;
    LibraryContextInteraction.triggerHaptic('Track');
    const epoch = ++this.contextMenuLoadEpoch;
    const trackId = this.track.id;
    this.loadContextMenu(epoch, trackId);
  }

  private async loadContextMenu(epoch: number, trackId: number): Promise<void> {
    try {
      const targets = await this.store.getTrackNavigationTargets(trackId);
      if (epoch !== this.contextMenuLoadEpoch || trackId !== this.track.id) {
        return;
      }
      this.linkActions = targets === undefined ? [] : libraryLinkActions(targets, undefined);
    } catch (error) {
      if (epoch !== this.contextMenuLoadEpoch || trackId !== this.track.id) {
        return;
      }
      this.linkActions = [];
      console.warn(`Unable to load queue context actions: ${error}`);
    }
    this.contextMenuShown = true;
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
  private Artwork() {
    ArtworkView({
      sourcePath: this.artworkPath,
      sourceWidth: this.track.artworkWidth,
      sourceHeight: this.track.artworkHeight,
      slotWidth: this.artworkSize,
      fitMode: ArtworkFitMode.CONTAIN,
      cornerRadius: this.artworkCornerRadius
    })
  }

  @Builder
  private IdentityContent() {
    Row({ space: 10 }) {
      this.QueuePosition()
      this.Artwork()
      Column({ space: LibraryTrackRowStyle.ALBUM_TEXT_SPACE }) {
        Text(this.track.title)
          .fontSize(LibraryTrackRowStyle.LIBRARY_TITLE_SIZE)
          .fontWeight(this.active ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.primaryColor)
          .animation({
            duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
            curve: Curve.EaseInOut
          })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.artistLabel())
          .fontSize(LibraryTrackRowStyle.LIBRARY_SECONDARY_SIZE)
          .fontColor(this.secondaryColor)
          .animation({
            duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
            curve: Curve.EaseInOut
          })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
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
  private Duration() {
    Text(this.durationLabel())
      .fontSize(LibraryTrackRowStyle.LIBRARY_SECONDARY_SIZE)
      .fontColor(this.tertiaryColor)
      .animation({
        duration: this.animateColors ? PaletteMotionSpec.COLOR_TRANSITION_DURATION : 0,
        curve: Curve.EaseInOut
      })
  }

  @Builder
  private ContextMenuPreview() {
    Row() {
      this.IdentityContent()
    }
    .width(this.effectiveContextPreviewWidth())
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private ContextMenu() {
    TrackActionMenu(new TrackActionMenuParams(
      [this.track],
      this.linkActions,
      this.onNavigateAction,
      this.onRequestAddToPlaylist
    ))
  }

  @Builder
  private SelectionIndicator() {
    Stack() {
      SymbolGlyph(this.selected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(22)
        .fontColor([this.selected ? $r('app.color.theme_accent') : this.tertiaryColor])
    }
    .width(this.selectionMode ? LibraryTrackRowStyle.SELECTION_WIDTH : 0)
    .opacity(this.selectionMode ? 1 : 0)
    .translate({ x: this.selectionMode ? 0 : -12 })
    .margin({ right: this.selectionMode ? LibraryTrackRowStyle.SELECTION_GAP : 0 })
    .clip(true)
    .animation({ duration: 180, curve: Curve.EaseOut })
  }

  @Builder
  private RowContent() {
    this.SelectionIndicator()
    Row() {
      this.IdentityContent()
    }
    .layoutWeight(1)
    .clip(true)
    this.Duration()
  }

  @Builder
  private ContextMenuIdentity() {
    Row() {
      this.IdentityContent()
    }
    .layoutWeight(1)
    .id(this.contextPreviewAnchorId())
    .clip(true)
    .opacity(this.contextMenuShown ? 0 : 1)
    .bindContextMenu(
      this.contextMenuShown,
      this.ContextMenu(),
      {
        preview: this.ContextMenuPreview,
        placement: this.menuPlacement,
        previewBorderRadius: 0,
        previewAnimationOptions: {
          scale: [1, 1]
        },
        onDisappear: (): void => {
          this.contextMenuShown = false;
        }
      }
    )
  }

  @Builder
  private SelectionRow() {
    Row({ space: 10 }) {
      this.RowContent()
    }
    .width('100%')
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
    .opacity(LibraryItemAvailability.opacity(this.track.availability))
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({
          direction: PanDirection.Horizontal,
          distance: this.queueGestureDistance
        }),
        TapGesture().onAction(() => this.onToggleSelection(this.track))
      )
    )
  }

  @Builder
  private ActionRow() {
    Row({ space: 10 }) {
      this.ContextMenuIdentity()
      this.Duration()
    }
    .width('100%')
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
    .opacity(LibraryItemAvailability.opacity(this.track.availability))
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({
          direction: PanDirection.Horizontal,
          distance: this.queueGestureDistance
        }),
        LongPressGesture({
          repeat: false,
          duration: LibraryContextInteraction.LONG_PRESS_DURATION
        }).onAction(() => this.showContextMenu()),
        TapGesture().onAction(() => {
          if (Date.now() < this.suppressActivationUntil) {
            return;
          }
          this.onActivate(this.track);
        })
      )
    )
  }

  build() {
    if (this.selectionMode) {
      this.SelectionRow()
    } else {
      this.ActionRow()
    }
  }
}
