import {
  LibraryEntityIdentity,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { LibraryContextInteraction } from './LibraryContextInteraction';
import { LibraryItemAvailability } from './LibraryItemAvailability';
import {
  TrackActionMenu,
  TrackActionMenuParams
} from './TrackActionMenu';
import {
  LibraryLinkAction,
  libraryLinkActions
} from '../navigation/LibraryNavigation';
import { ContextPreviewGeometry } from './ContextPreviewGeometry';

export enum LibraryTrackRowVariant {
  LIBRARY = 0,
  ALBUM = 1
}

export class LibraryTrackRowStyle {
  static readonly LIBRARY_TITLE_SIZE: number = 16;
  static readonly ALBUM_TITLE_SIZE: number = 15;
  static readonly LIBRARY_SECONDARY_SIZE: number = 13;
  static readonly ALBUM_SECONDARY_SIZE: number = 12;
  static readonly DURATION_SIZE: number = 12;
  static readonly CONTENT_SPACE: number = 12;
  static readonly LIBRARY_TEXT_SPACE: number = 4;
  static readonly ALBUM_TEXT_SPACE: number = 3;
  static readonly SELECTION_WIDTH: number = 30;
  static readonly SELECTION_GAP: number = 8;
  static readonly ACTION_SIZE: number = 38;
  static readonly ACTION_ICON_SIZE: number = 18;
}

@Reusable
@Component
export struct LibraryTrackRow {
  @ObjectLink store: LibraryStore;
  @Prop track: TrackListItem;
  @Prop variant: LibraryTrackRowVariant = LibraryTrackRowVariant.LIBRARY;
  @Prop currentIdentity: LibraryEntityIdentity | undefined = undefined;
  @Prop artworkPath: string = '';
  @Prop trackNumber: number = 0;
  @Prop showArtist: boolean = true;
  @Prop actionAnchorPrefix: string = 'library';
  @Prop menuPlacement: Placement = Placement.BottomLeft;
  @Prop horizontalInset: number = 16;
  @Prop verticalInset: number = 8;
  @Prop minimumHeight: number = 0;
  @Prop rowCornerRadius: number = 0;
  @Prop artworkSize: number = 52;
  @Prop artworkCornerRadius: number = 10;
  @Prop removeActionLabel: string = '';
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  @Prop primaryColor: ResourceColor = $r('app.color.text_primary');
  @Prop secondaryColor: ResourceColor = $r('app.color.text_secondary');
  @Prop tertiaryColor: ResourceColor = $r('app.color.text_tertiary');
  onActivate: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onToggleSelection: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onOpenActions: (track: TrackListItem, anchorId: string) => void =
    (_track: TrackListItem, _anchorId: string): void => {};
  onNavigateAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onOpenDetails: ((track: TrackListItem) => void) | undefined = undefined;
  onRemoveAction: (() => void) | undefined = undefined;
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
    this.onOpenActions =
      params.onOpenActions as (track: TrackListItem, anchorId: string) => void;
    this.onNavigateAction =
      params.onNavigateAction as (target: LibraryNavigationTarget) => void;
    this.onRequestAddToPlaylist =
      params.onRequestAddToPlaylist as (items: Array<TrackListItem>) => void;
    this.onOpenDetails =
      params.onOpenDetails as ((track: TrackListItem) => void) | undefined;
    this.onRemoveAction = params.onRemoveAction as (() => void) | undefined;
  }

  aboutToRecycle(): void {
    this.contextMenuLoadEpoch += 1;
  }

  private titleSize(): number {
    return this.variant === LibraryTrackRowVariant.ALBUM ?
      LibraryTrackRowStyle.ALBUM_TITLE_SIZE : LibraryTrackRowStyle.LIBRARY_TITLE_SIZE;
  }

  private secondarySize(): number {
    return this.variant === LibraryTrackRowVariant.ALBUM ?
      LibraryTrackRowStyle.ALBUM_SECONDARY_SIZE : LibraryTrackRowStyle.LIBRARY_SECONDARY_SIZE;
  }

  private textSpace(): number {
    return this.variant === LibraryTrackRowVariant.ALBUM ?
      LibraryTrackRowStyle.ALBUM_TEXT_SPACE : LibraryTrackRowStyle.LIBRARY_TEXT_SPACE;
  }

  private artistLabel(): string {
    const unavailableLabel = LibraryItemAvailability.label(this.track.availability);
    if (unavailableLabel.length > 0) {
      return unavailableLabel;
    }
    return this.track.artistDisplay.trim().length > 0 ? this.track.artistDisplay : '未知艺术家';
  }

  private durationLabel(): string {
    const totalSeconds = Math.max(0, Math.floor(this.track.durationMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private actionAnchorId(): string {
    return `track_more_${this.actionAnchorPrefix}_${this.track.id}`;
  }

  private showContextMenu(event: GestureEvent): void {
    const frame = ContextPreviewGeometry.fromGesture(event);
    if (frame.width <= 0) {
      console.warn('Unable to measure track context preview from gesture target');
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
      if (epoch !== this.contextMenuLoadEpoch || trackId !== this.track.id) {
        return;
      }
      this.linkActions =
        targets === undefined ? [] : libraryLinkActions(targets, this.currentIdentity);
    } catch (error) {
      if (epoch !== this.contextMenuLoadEpoch || trackId !== this.track.id) {
        return;
      }
      this.linkActions = [];
      console.warn(`Unable to load track context actions: ${error}`);
    }
    this.contextMenuShown = true;
  }

  @Builder
  private LeadingContent() {
    if (this.variant === LibraryTrackRowVariant.ALBUM) {
      Text(this.trackNumber > 0 ? `${this.trackNumber}` : '-')
        .fontSize(13)
        .fontColor(this.secondaryColor)
        .width(30)
        .textAlign(TextAlign.Center)
    } else {
      ArtworkView({
        sourcePath: this.artworkPath,
        sourceWidth: this.track.artworkWidth,
        sourceHeight: this.track.artworkHeight,
        slotWidth: this.artworkSize,
        fitMode: ArtworkFitMode.CONTAIN,
        cornerRadius: this.artworkCornerRadius
      })
    }
  }

  @Builder
  private IdentityContent() {
    Row({ space: LibraryTrackRowStyle.CONTENT_SPACE }) {
      this.LeadingContent()
      Column({ space: this.textSpace() }) {
        Text(this.track.title)
          .fontSize(this.titleSize())
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.showArtist) {
          Text(this.artistLabel())
            .fontSize(this.secondarySize())
            .fontColor(this.secondaryColor)
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
  private ContextMenuPreview() {
    Row({ space: LibraryTrackRowStyle.CONTENT_SPACE }) {
      this.LeadingContent()
      Column({ space: this.textSpace() }) {
        Text(this.track.title)
          .fontSize(this.titleSize())
          .fontWeight(FontWeight.Medium)
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
    .width(this.measuredIdentityWidth)
  }

  @Builder
  private ContextMenu() {
    TrackActionMenu(new TrackActionMenuParams(
      [this.track],
      this.linkActions,
      this.onNavigateAction,
      this.onRequestAddToPlaylist,
      this.removeActionLabel,
      this.onRemoveAction,
      this.onOpenDetails
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
  private TrailingContent() {
    if (LibraryItemAvailability.unavailable(this.track.availability)) {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(17)
        .fontColor([this.tertiaryColor])
    }
    Text(this.durationLabel())
      .fontSize(LibraryTrackRowStyle.DURATION_SIZE)
      .fontColor(this.tertiaryColor)
    if (!this.selectionMode) {
      Button() {
        Image($r('app.media.control_more'))
          .width(LibraryTrackRowStyle.ACTION_ICON_SIZE)
          .height(LibraryTrackRowStyle.ACTION_ICON_SIZE)
          .fillColor(this.primaryColor)
      }
      .width(LibraryTrackRowStyle.ACTION_SIZE)
      .height(LibraryTrackRowStyle.ACTION_SIZE)
      .borderRadius(LibraryTrackRowStyle.ACTION_SIZE / 2)
      .backgroundColor(Color.Transparent)
      .accessibilityText('更多歌曲操作')
      .id(this.actionAnchorId())
      .onClick(() => this.onOpenActions(this.track, this.actionAnchorId()))
    }
  }

  @Builder
  private InteractiveIdentity() {
    Row() {
      this.IdentityContent()
    }
    .layoutWeight(1)
    .clip(true)
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

  build() {
    Row({ space: LibraryTrackRowStyle.CONTENT_SPACE }) {
      this.SelectionIndicator()
      if (this.selectionMode) {
        Row() {
          this.IdentityContent()
        }
        .layoutWeight(1)
        .clip(true)
      } else {
        this.InteractiveIdentity()
      }
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
    .opacity(LibraryItemAvailability.opacity(this.track.availability))
    .onClick(() => {
      if (Date.now() < this.suppressActivationUntil) {
        return;
      }
      if (this.selectionMode) {
        this.onToggleSelection(this.track);
      } else {
        this.onActivate(this.track);
      }
    })
  }
}
