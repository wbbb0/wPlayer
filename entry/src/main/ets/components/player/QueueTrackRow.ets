import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
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
import { QueueEntryPresentation } from '../../playback/model/PlaybackModels';
import { LibrarySelectionIndicator } from '../library/LibrarySelectionIndicator';

@Reusable
@Component
export struct QueueTrackRow {
  @ObjectLink store: LibraryStore;
  @ObjectLink presentation: QueueEntryPresentation;
  @Prop track: TrackListItem;
  @Prop artworkPath: string = '';
  @Prop primaryColor: ResourceColor = $r('app.color.text_primary');
  @Prop secondaryColor: ResourceColor = $r('app.color.text_secondary');
  @Prop tertiaryColor: ResourceColor = $r('app.color.text_tertiary');
  @Prop animateColors: boolean = false;
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
    this.onOpenDetails = params.onOpenDetails as (track: TrackListItem) => void;
    this.onShareTrackFile = params.onShareTrackFile as (trackId: number) => void;
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
    if (this.presentation.displayIndex <= this.presentation.currentDisplayIndex) {
      return '';
    }
    return `${this.presentation.displayIndex - this.presentation.currentDisplayIndex}`;
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
      if (this.presentation.isActive()) {
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
          .fontWeight(this.presentation.isActive() ? FontWeight.Bold : FontWeight.Medium)
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
      trailingGap: LibraryTrackRowStyle.SELECTION_GAP + 10
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
    .backgroundColor(this.presentation.isActive() ? this.activeBackgroundColor : Color.Transparent)
    .shadow(this.presentation.isActive() ? {
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
