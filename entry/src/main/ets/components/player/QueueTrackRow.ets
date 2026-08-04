import {
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { ContextPreviewGeometry } from '../library/ContextPreviewGeometry';
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
import {
  QueueProjectionState
} from '../../playback/model/PlaybackModels';
import { LibrarySelectionIndicator } from '../library/LibrarySelectionIndicator';

@Reusable
@Component
export struct QueueTrackRow {
  @ObjectLink store: LibraryStore;
  @ObjectLink projection: QueueProjectionState;
  @Prop @Watch('onEntryIdChanged') entryId: number = -1;
  @Prop selectionTargetKey: number = -1;
  @Prop track: TrackListItem;
  @Prop artworkPath: string = '';
  @Prop primaryColor: ResourceColor = $r('app.color.text_primary');
  @Prop secondaryColor: ResourceColor = $r('app.color.text_secondary');
  @Prop tertiaryColor: ResourceColor = $r('app.color.text_tertiary');
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
  @Prop menuPlacement: Placement = Placement.BottomLeft;
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  onActivate: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onToggleSelection: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onSelectionTargetAreaChange: (targetKey: number, entryId: number, area: Area) => void =
    (_targetKey: number, _entryId: number, _area: Area): void => {};
  onSelectionTargetRemoved: (targetKey: number) => void = (_targetKey: number): void => {};
  onSelectionDragStart: (entryId: number, x: number, y: number) => void =
    (_entryId: number, _x: number, _y: number): void => {};
  onSelectionDragUpdate: (x: number, y: number) => void = (_x: number, _y: number): void => {};
  onSelectionDragEnd: () => void = (): void => {};
  onSelectionDragCancel: () => void = (): void => {};
  onNavigateAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onOpenDetails: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  @State contextMenuShown: boolean = false;
  @State linkActions: Array<LibraryLinkAction> = [];
  private measuredIdentityWidth: number = 0;
  private suppressActivationUntil: number = 0;
  private contextMenuLoadEpoch: number = 0;
  private renderedEntryId: number = -1;
  private selectionTargetArea?: Area;

  aboutToAppear(): void {
    this.renderedEntryId = this.entryId;
  }

  private onEntryIdChanged(): void {
    this.resetEntryBoundState(false);
    this.renderedEntryId = this.entryId;
    if (this.selectionTargetArea !== undefined) {
      this.onSelectionTargetAreaChange(
        this.selectionTargetKey,
        this.entryId,
        this.selectionTargetArea
      );
    }
  }

  private resetEntryBoundState(clearSelectionArea: boolean = true): void {
    if (this.renderedEntryId >= 0) {
      this.onSelectionTargetRemoved(this.selectionTargetKey);
    }
    this.contextMenuLoadEpoch += 1;
    this.contextMenuShown = false;
    this.linkActions = [];
    this.measuredIdentityWidth = 0;
    this.suppressActivationUntil = 0;
    if (clearSelectionArea) {
      this.selectionTargetArea = undefined;
    }
  }

  private updateSelectionTargetArea(area: Area): void {
    this.selectionTargetArea = area;
    this.onSelectionTargetAreaChange(this.selectionTargetKey, this.entryId, area);
  }

  aboutToReuse(params: ESObject): void {
    this.resetEntryBoundState();
    this.onActivate = params.onActivate as (track: TrackListItem) => void;
    this.onToggleSelection = params.onToggleSelection as (track: TrackListItem) => void;
    this.onSelectionTargetAreaChange = typeof params.onSelectionTargetAreaChange === 'function' ?
      params.onSelectionTargetAreaChange as (targetKey: number, entryId: number, area: Area) => void :
      (_targetKey: number, _entryId: number, _area: Area): void => {};
    this.onSelectionTargetRemoved = typeof params.onSelectionTargetRemoved === 'function' ?
      params.onSelectionTargetRemoved as (entryId: number) => void : (_entryId: number): void => {};
    this.onSelectionDragStart = typeof params.onSelectionDragStart === 'function' ?
      params.onSelectionDragStart as (entryId: number, x: number, y: number) => void :
      (_entryId: number, _x: number, _y: number): void => {};
    this.onSelectionDragUpdate = typeof params.onSelectionDragUpdate === 'function' ?
      params.onSelectionDragUpdate as (x: number, y: number) => void : (_x: number, _y: number): void => {};
    this.onSelectionDragEnd = typeof params.onSelectionDragEnd === 'function' ?
      params.onSelectionDragEnd as () => void : (): void => {};
    this.onSelectionDragCancel = typeof params.onSelectionDragCancel === 'function' ?
      params.onSelectionDragCancel as () => void : (): void => {};
    this.onNavigateAction =
      params.onNavigateAction as (target: LibraryNavigationTarget) => void;
    this.onRequestAddToPlaylist =
      params.onRequestAddToPlaylist as (items: Array<TrackListItem>) => void;
    this.onOpenDetails = params.onOpenDetails as (track: TrackListItem) => void;
    this.onShareTrackFile = params.onShareTrackFile as (trackId: number) => void;
  }

  aboutToRecycle(): void {
    this.resetEntryBoundState();
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
    const displayIndex = this.projection.displayIndex(this.entryId);
    const currentDisplayIndex = this.projection.activeIndex();
    if (displayIndex <= currentDisplayIndex) {
      return '';
    }
    return `${displayIndex - currentDisplayIndex}`;
  }

  private isActive(): boolean {
    return this.projection.isActive(this.entryId);
  }

  private showContextMenu(event: GestureEvent): void {
    if (this.selectionMode) {
      return;
    }
    const frame = ContextPreviewGeometry.fromGesture(event);
    if (frame.width <= 0) {
      console.warn('Unable to measure queue context preview from gesture target');
      return;
    }
    this.measuredIdentityWidth = frame.width;
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
      if (epoch !== this.contextMenuLoadEpoch || trackId !== this.track.id || this.selectionMode) {
        return;
      }
      this.linkActions = targets === undefined ? [] : libraryLinkActions(targets, undefined);
    } catch (error) {
      if (epoch !== this.contextMenuLoadEpoch || trackId !== this.track.id || this.selectionMode) {
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
      if (this.isActive()) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(16)
          .fontColor([this.primaryColor])
      } else {
        Text(this.queuePositionLabel())
          .fontSize(12)
          .fontColor(this.secondaryColor)
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
          .fontWeight(this.isActive() ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.primaryColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.artistLabel())
          .fontSize(LibraryTrackRowStyle.LIBRARY_SECONDARY_SIZE)
          .fontColor(this.secondaryColor)
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
  }

  @Builder
  private ContextMenuPreview() {
    Row() {
      this.IdentityContent()
    }
    .width(this.measuredIdentityWidth)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private ContextMenu() {
    TrackActionMenu(new TrackActionMenuParams({
      queueItems: [this.track],
      linkActions: this.linkActions,
      onNavigate: this.onNavigateAction,
      onRequestAddToPlaylist: this.onRequestAddToPlaylist,
      removeLabel: '',
      onOpenDetails: this.onOpenDetails,
      onShareFile: (): void => this.onShareTrackFile(this.track.id)
    }))
  }

  @Builder
  private SelectionIndicator() {
    LibrarySelectionIndicator({
      selectionMode: this.selectionMode,
      selected: this.selected,
      unselectedColor: this.tertiaryColor,
      slotWidth: LibraryTrackRowStyle.SELECTION_WIDTH,
      trailingGap: LibraryTrackRowStyle.SELECTION_GAP + 10,
      onSelectionPanStart: (x: number, y: number): void =>
        this.onSelectionDragStart(this.entryId, x, y),
      onSelectionPanUpdate: this.onSelectionDragUpdate,
      onSelectionPanEnd: this.onSelectionDragEnd,
      onSelectionPanCancel: this.onSelectionDragCancel
    })
  }

  @Builder
  private ContextMenuIdentity() {
    Row() {
      this.IdentityContent()
    }
    .layoutWeight(1)
    .clip(true)
    .margin({ right: 10 })
    .opacity(this.contextMenuShown ? 0 : 1)
    .bindContextMenu(
      this.contextMenuShown,
      this.ContextMenu(),
      {
        preview: this.ContextMenuPreview,
        placement: this.menuPlacement,
        previewBorderRadius: 0,
        layoutRegionMargin: ContextPreviewGeometry.layoutRegionMargin(),
        previewAnimationOptions: ContextPreviewGeometry.animationOptions(),
        onDisappear: (): void => {
          this.contextMenuShown = false;
        }
      }
    )
    .gesture(
      LongPressGesture({
        repeat: false,
        duration: LibraryContextInteraction.LONG_PRESS_DURATION
      }).onAction((event: GestureEvent) => this.showContextMenu(event))
    )
  }

  @Builder
  private StableRow() {
    Row() {
      this.SelectionIndicator()
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
    .backgroundColor(this.isActive() ? this.activeBackgroundColor : Color.Transparent)
    .shadow(this.isActive() ? {
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
    .onAreaChange((_oldValue: Area, newValue: Area): void =>
      this.updateSelectionTargetArea(newValue))
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        PanGesture({
          direction: PanDirection.Horizontal,
          distance: this.queueGestureDistance
        }),
        TapGesture().onAction(() => {
          if (Date.now() < this.suppressActivationUntil) {
            return;
          }
          if (this.selectionMode) {
            this.onToggleSelection(this.track);
          } else {
            this.onActivate(this.track);
          }
        })
      )
    )
  }

  build() {
    this.StableRow()
  }
}
