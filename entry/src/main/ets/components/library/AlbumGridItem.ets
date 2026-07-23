import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { PageLayoutSpec } from '../layout/PageLayoutSpec';
import {
  AlbumListItem,
  ArtistReference,
  LibraryNavigationTarget
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { artistTarget } from '../navigation/LibraryNavigation';
import { LayoutLength } from '../layout/LayoutLength';
import { LibraryItemAvailability } from './LibraryItemAvailability';
import { AvailabilityState } from '../../library/model/LibraryModels';
import { LibraryContextInteraction } from './LibraryContextInteraction';

export enum AlbumAction {
  INSERT_NEXT = 0,
  APPEND_QUEUE = 1,
  ADD_TO_PLAYLIST = 2
}

@Component
struct AlbumContextMenu {
  @ObjectLink store: LibraryStore;
  @Prop album: AlbumListItem;
  @State artists: Array<ArtistReference> = [];
  onAction: (album: AlbumListItem, action: AlbumAction) => void =
    (_album: AlbumListItem, _action: AlbumAction): void => {};
  onNavigate: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.loadArtists();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private async loadArtists(): Promise<void> {
    try {
      const artists = await this.store.getAlbumArtists(this.album.id);
      if (this.active) {
        this.artists = artists;
      }
    } catch (error) {
      if (this.active) {
        this.artists = [];
      }
      console.warn(`Unable to load album context actions: ${error instanceof Error ? error.message : `${error}`}`);
    }
  }

  build() {
    Menu() {
      MenuItem({ content: '插播', labelInfo: '下一首开始' })
        .onClick(() => this.onAction(this.album, AlbumAction.INSERT_NEXT))
      MenuItem({ content: '追加到队列' })
        .onClick(() => this.onAction(this.album, AlbumAction.APPEND_QUEUE))
      MenuItem({ content: '添加到播放列表' })
        .onClick(() => this.onAction(this.album, AlbumAction.ADD_TO_PLAYLIST))
      ForEach(this.artists, (artist: ArtistReference) => {
        MenuItem({ content: `前往艺术家：${artist.name}` })
          .onClick(() => this.onNavigate(artistTarget(artist)))
      }, (artist: ArtistReference) => `${artist.id}`)
    }
    .width(260)
  }
}

@Reusable
@Component
export struct AlbumGridItem {
  @State contextMenuShown: boolean = false;
  private measuredItemWidth: number = 0;
  private measuredItemHeight: number = 0;
  private suppressActivationUntil: number = 0;
  @ObjectLink store: LibraryStore;
  @Prop album: AlbumListItem;
  @Prop actionsEnabled: boolean = false;
  @Prop actionAnchorPrefix: string = 'album_grid';
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  onActivate: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onToggleSelection: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onAction: (album: AlbumListItem, action: AlbumAction) => void =
    (_album: AlbumListItem, _action: AlbumAction): void => {};
  onNavigate: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};

  aboutToReuse(params: ESObject): void {
    this.contextMenuShown = false;
    this.measuredItemWidth = 0;
    this.measuredItemHeight = 0;
    this.suppressActivationUntil = 0;
    this.onActivate = params.onActivate as (album: AlbumListItem) => void;
    this.onToggleSelection = params.onToggleSelection as (album: AlbumListItem) => void;
    this.onAction = params.onAction as (album: AlbumListItem, action: AlbumAction) => void;
    this.onNavigate = params.onNavigate as (target: LibraryNavigationTarget) => void;
  }

  @Builder
  private AlbumMenu() {
    AlbumContextMenu({
      store: this.store,
      album: this.album,
      onAction: this.onAction,
      onNavigate: this.onNavigate
    })
  }

  @Builder
  private AlbumVisualContent() {
    Column({ space: 7 }) {
      ArtworkView({
        sourcePath: this.album.artworkPath.length > 0 ?
          this.store.resolveArtworkPath(this.album.artworkPath) : '',
        sourceWidth: this.album.artworkWidth,
        sourceHeight: this.album.artworkHeight,
        fitMode: ArtworkFitMode.CONTAIN,
        cornerRadius: 18,
        shadowEnabled: this.album.artworkPath.length > 0
      })
      Text(this.album.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(this.album.albumArtistDisplay.length > 0 ?
        (this.album.unavailableTrackCount > 0 ?
          `${this.album.albumArtistDisplay} · ${this.album.unavailableTrackCount} 首不可用` :
          this.album.albumArtistDisplay) :
        (this.albumUnavailable() ? '文件均不可用' :
          (this.album.unavailableTrackCount > 0 ?
            `${this.album.unavailableTrackCount} 首不可用` : `${this.album.trackCount} 首`)))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .opacity(LibraryItemAvailability.opacity(
      this.albumUnavailable() ? AvailabilityState.UNAVAILABLE : AvailabilityState.AVAILABLE
    ))
  }

  @Builder
  private AlbumContextPreview() {
    if (this.measuredItemWidth > 0 && this.measuredItemHeight > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.AlbumVisualContent()
      }
      .width(this.measuredItemWidth)
      .height(this.measuredItemHeight)
    } else {
      this.AlbumVisualContent()
    }
  }

  private contextPreviewAnchorId(): string {
    return `album_context_preview_${this.actionAnchorPrefix}_${this.album.id}`;
  }

  private showContextMenu(): void {
    try {
      const uiContext = this.getUIContext();
      const info = uiContext.getComponentUtils()
        .getRectangleById(this.contextPreviewAnchorId());
      const widthPx = LayoutLength.toNumber(info.size.width, 0);
      const heightPx = LayoutLength.toNumber(info.size.height, 0);
      const width = uiContext.px2vp(widthPx);
      const height = uiContext.px2vp(heightPx);
      if (width > 0) {
        this.measuredItemWidth = width;
      }
      if (height > 0) {
        this.measuredItemHeight = height;
      }
    } catch (error) {
      console.warn(`Unable to measure album context preview: ${error}`);
    }
    this.suppressActivationUntil =
      Date.now() + LibraryContextInteraction.ACTIVATION_SUPPRESSION_DURATION;
    LibraryContextInteraction.triggerHaptic('Album');
    this.contextMenuShown = true;
  }

  private albumUnavailable(): boolean {
    return this.album.trackCount > 0 &&
      this.album.unavailableTrackCount >= this.album.trackCount;
  }

  @Builder
  private SelectableAlbumContent() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.AlbumVisualContent()
      SymbolGlyph(this.selected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(26)
        .fontColor([this.selected ? $r('app.color.theme_accent') : $r('app.color.text_secondary')])
        .backgroundColor($r('app.color.glass_surface_strong'))
        .borderRadius(15)
        .margin({ top: 8, left: 8 })
        .opacity(this.selectionMode ? 1 : 0)
        .translate({ x: this.selectionMode ? 0 : -10 })
        .scale({ x: this.selectionMode ? 1 : 0.7, y: this.selectionMode ? 1 : 0.7 })
        .animation({ duration: 180, curve: Curve.EaseOut })
    }
    .width('100%')
    .onClick(() => {
      if (Date.now() < this.suppressActivationUntil) {
        return;
      }
      if (this.selectionMode) {
        this.onToggleSelection(this.album);
      } else {
        this.onActivate(this.album);
      }
    })
  }

  build() {
    if (this.actionsEnabled && !this.selectionMode) {
      Stack() {
        Stack() {
          this.SelectableAlbumContent()
        }
        .width('100%')
        .opacity(this.contextMenuShown ? 0 : 1)
      }
        .width('100%')
        .id(this.contextPreviewAnchorId())
        .bindContextMenu(
          this.contextMenuShown,
          this.AlbumMenu(),
          {
            preview: this.AlbumContextPreview,
            previewBorderRadius: 0,
            onDisappear: (): void => {
              this.contextMenuShown = false;
            }
          }
        )
        .gesture(
          LongPressGesture({
            repeat: false,
            duration: LibraryContextInteraction.LONG_PRESS_DURATION
          })
            .onAction(() => {
              this.showContextMenu();
            })
        )
    } else {
      this.SelectableAlbumContent()
    }
  }
}

@Component
export struct AlbumGridSection {
  @ObjectLink store: LibraryStore;
  @Prop albums: Array<AlbumListItem> = [];
  @Prop containerWidth: number = 0;
  @State measuredContainerWidth: number = 0;
  @Prop horizontalInset: number = PageLayoutSpec.HORIZONTAL_INSET;
  @Prop actionsEnabled: boolean = false;
  @Prop actionAnchorPrefix: string = 'album_section';
  onOpenAlbum: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onAlbumAction: (album: AlbumListItem, action: AlbumAction) => void =
    (_album: AlbumListItem, _action: AlbumAction): void => {};
  onNavigate: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};

  private columnCount(): number {
    return PageLayoutSpec.albumColumnCount(this.effectiveContainerWidth(), this.horizontalInset);
  }

  private itemWidth(): number {
    return PageLayoutSpec.albumItemWidth(this.effectiveContainerWidth(), this.horizontalInset);
  }

  private effectiveContainerWidth(): number {
    return this.measuredContainerWidth > 0 ? this.measuredContainerWidth : this.containerWidth;
  }

  private rowStarts(): Array<number> {
    const values: Array<number> = [];
    const columnCount = this.columnCount();
    for (let index = 0; index < this.albums.length; index += columnCount) {
      values.push(index);
    }
    return values;
  }

  @Builder
  private AlbumRow(startIndex: number) {
    Row({ space: PageLayoutSpec.ALBUM_COLUMN_GAP }) {
      ForEach(
        this.albums.slice(startIndex, startIndex + this.columnCount()),
        (album: AlbumListItem) => {
          AlbumGridItem({
            store: this.store,
            album: album,
            actionsEnabled: this.actionsEnabled,
            actionAnchorPrefix: this.actionAnchorPrefix,
            onActivate: this.onOpenAlbum,
            onAction: this.onAlbumAction,
            onNavigate: this.onNavigate
          })
            .width(this.itemWidth())
        },
        (album: AlbumListItem) => `${album.id}`
      )
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  build() {
    Column({ space: PageLayoutSpec.ALBUM_ROW_GAP }) {
      ForEach(this.rowStarts(), (startIndex: number) => {
        this.AlbumRow(startIndex)
      }, (startIndex: number) => `${startIndex}`)
    }
    .width('100%')
    .padding({
      left: this.horizontalInset,
      right: this.horizontalInset
    })
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const nextWidth = LayoutLength.toNumber(newValue.width, this.measuredContainerWidth);
      if (nextWidth > 0 && Math.abs(nextWidth - this.measuredContainerWidth) >= 0.5) {
        this.measuredContainerWidth = nextWidth;
      }
    })
  }
}
