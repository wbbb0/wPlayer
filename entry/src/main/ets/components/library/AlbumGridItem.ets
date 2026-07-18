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

@Component
export struct AlbumGridItem {
  @ObjectLink store: LibraryStore;
  @Prop album: AlbumListItem;
  @Prop actionsEnabled: boolean = false;
  @Prop actionAnchorPrefix: string = 'album_grid';
  onActivate: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onAction: (album: AlbumListItem, action: AlbumAction) => void =
    (_album: AlbumListItem, _action: AlbumAction): void => {};
  onNavigate: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};

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
  private AlbumContent() {
    Column({ space: 7 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        ArtworkView({
          sourcePath: this.album.artworkPath.length > 0 ?
            this.store.resolveArtworkPath(this.album.artworkPath) : '',
          sourceWidth: this.album.artworkWidth,
          sourceHeight: this.album.artworkHeight,
          fitMode: ArtworkFitMode.CONTAIN,
          cornerRadius: 18,
          shadowEnabled: this.album.artworkPath.length > 0
        })
        if (this.actionsEnabled) {
          Button() {
            Image($r('app.media.control_more'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_primary'))
          }
          .id(`${this.actionAnchorPrefix}_${this.album.id}`)
          .width(38)
          .height(38)
          .margin(8)
          .borderRadius(19)
          .backgroundColor($r('app.color.glass_surface_strong'))
          .accessibilityText('更多专辑操作')
          .bindMenu(this.AlbumMenu(), { placement: Placement.BottomRight })
        }
      }
      .width('100%')
      Text(this.album.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .width('100%')
      Text(this.album.albumArtistDisplay.length > 0 ?
        this.album.albumArtistDisplay : `${this.album.trackCount} 首`)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => this.onActivate(this.album))
  }

  build() {
    if (this.actionsEnabled) {
      Stack() {
        this.AlbumContent()
      }
        .width('100%')
        .bindContextMenu(
          this.AlbumMenu(),
          ResponseType.LongPress,
          {
            preview: MenuPreviewMode.IMAGE,
            previewBorderRadius: 0
          }
        )
    } else {
      this.AlbumContent()
    }
  }
}

@Component
export struct AlbumGridItemPlaceholder {
  build() {
    Column({ space: 7 }) {
      Row()
        .width('100%')
        .aspectRatio(1)
        .borderRadius(18)
        .backgroundColor($r('app.color.text_tertiary'))
        .opacity(0.12)
      Row()
        .width('68%')
        .height(12)
        .borderRadius(6)
        .backgroundColor($r('app.color.text_tertiary'))
        .opacity(0.14)
      Row()
        .width('46%')
        .height(10)
        .borderRadius(5)
        .backgroundColor($r('app.color.text_tertiary'))
        .opacity(0.1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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
