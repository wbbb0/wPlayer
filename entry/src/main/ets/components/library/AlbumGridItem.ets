import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { PageLayoutSpec } from '../layout/PageLayoutSpec';
import { AlbumListItem } from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct AlbumGridItem {
  @ObjectLink store: LibraryStore;
  @Prop album: AlbumListItem;
  onActivate: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};

  build() {
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
  @Prop horizontalInset: number = PageLayoutSpec.HORIZONTAL_INSET;
  onOpenAlbum: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};

  private columnCount(): number {
    return PageLayoutSpec.albumColumnCount(this.containerWidth, this.horizontalInset);
  }

  private itemWidth(): number {
    return PageLayoutSpec.albumItemWidth(this.containerWidth, this.horizontalInset);
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
            onActivate: this.onOpenAlbum
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
  }
}
