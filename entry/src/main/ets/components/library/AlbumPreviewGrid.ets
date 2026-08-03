import { PageLayoutSpec } from '../layout/PageLayoutSpec';
import { AlbumListItem, LibraryNavigationTarget } from '../../library/model/LibraryModels';
import { LibraryListDataSource } from '../../library/store/LibraryListDataSource';
import { LibraryStore } from '../../library/store/LibraryStore';
import { AlbumAction, AlbumGridItem } from './AlbumGridItem';

export class AlbumPreviewLayoutPolicy {
  static readonly MIN_ITEM_WIDTH: number = 148;
  static readonly MAX_ITEM_WIDTH: number = 184;
  static readonly CARD_TEXT_HEIGHT: number = 48;

  static itemWidth(containerWidth: number): number {
    const available = Math.max(0, containerWidth - PageLayoutSpec.HORIZONTAL_INSET * 2);
    return Math.max(
      AlbumPreviewLayoutPolicy.MIN_ITEM_WIDTH,
      Math.min(AlbumPreviewLayoutPolicy.MAX_ITEM_WIDTH, available * 0.43)
    );
  }

  static viewportHeight(containerWidth: number): number {
    const rowHeight = AlbumPreviewLayoutPolicy.itemWidth(containerWidth) +
      AlbumPreviewLayoutPolicy.CARD_TEXT_HEIGHT;
    return rowHeight * 2 + PageLayoutSpec.ALBUM_ROW_GAP;
  }
}

@Component
export struct AlbumPreviewGrid {
  @ObjectLink store: LibraryStore;
  @Prop @Watch('syncAlbums') albums: Array<AlbumListItem> = [];
  @Prop containerWidth: number = 0;
  @Prop primaryColor: ResourceColor = $r('app.color.text_primary');
  @Prop secondaryColor: ResourceColor = $r('app.color.text_secondary');
  private readonly dataSource: LibraryListDataSource<AlbumListItem> =
    new LibraryListDataSource<AlbumListItem>();
  onOpenAlbum: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onAlbumAction: (album: AlbumListItem, action: AlbumAction) => void =
    (_album: AlbumListItem, _action: AlbumAction): void => {};
  onNavigate: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};

  aboutToAppear(): void {
    this.syncAlbums();
  }

  private syncAlbums(): void {
    this.dataSource.replace(this.albums);
  }

  build() {
    Grid() {
      LazyForEach(this.dataSource, (album: AlbumListItem) => {
        GridItem() {
          AlbumGridItem({
            store: this.store,
            album: album,
            actionsEnabled: true,
            artworkShadowEnabled: false,
            primaryColor: this.primaryColor,
            secondaryColor: this.secondaryColor,
            onActivate: this.onOpenAlbum,
            onAction: this.onAlbumAction,
            onNavigate: this.onNavigate
          })
        }
        .width(AlbumPreviewLayoutPolicy.itemWidth(this.containerWidth))
      }, (album: AlbumListItem) => this.dataSource.keyFor(album.id))
    }
    .rowsTemplate('1fr 1fr')
    .columnsGap(PageLayoutSpec.ALBUM_COLUMN_GAP)
    .rowsGap(PageLayoutSpec.ALBUM_ROW_GAP)
    .width('100%')
    .height(AlbumPreviewLayoutPolicy.viewportHeight(this.containerWidth))
    .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
    .cachedCount(2, true)
  }
}
