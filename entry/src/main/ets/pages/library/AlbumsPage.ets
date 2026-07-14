import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageGridBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryAlphabetIndex } from '../../components/library/LibraryAlphabetIndex';
import {
  AlbumListItem,
  LibraryIndexPresentation
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct AlbumsPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageGridBehavior = new PageGridBehavior();
  @Builder
  private Artwork(item: AlbumListItem) {
    if (item.artworkPath.length > 0) {
      Image(this.store.resolveArtworkPath(item.artworkPath))
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(18)
    } else {
      Image($r('app.media.default_album_cover'))
        .width('100%')
        .aspectRatio(1)
        .objectFit(ImageFit.Cover)
        .borderRadius(18)
    }
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.End }) {
        Grid(this.scroller) {
          LazyForEach(this.store.albumDataSource, (item: AlbumListItem) => {
            GridItem() {
              Column({ space: 7 }) {
                this.Artwork(item)
                Text(item.title)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .width('100%')
                Text(item.albumArtistDisplay.length > 0 ? item.albumArtistDisplay : `${item.trackCount} 首`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
            }
          }, (item: AlbumListItem) => `${item.id}`)
        }
        .columnsTemplate(PageLayoutSpec.albumColumnsTemplate())
        .columnsGap(16)
        .rowsGap(20)
        .width('100%')
        .height('100%')
        .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET })
        .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
        .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
        .scrollBar(this.store.albumIndexPresentation === LibraryIndexPresentation.ALPHABET ?
          BarState.Off : BarState.Auto)
        .attributeModifier(this.scrollBehavior)

        if (this.store.albumIndexPresentation === LibraryIndexPresentation.ALPHABET &&
          this.store.albumSections.length > 0) {
          LibraryAlphabetIndex({
            sections: this.store.albumSections,
            onSelect: (itemIndex: number) => {
              this.scroller.scrollToIndex(itemIndex, false, ScrollAlign.START);
            }
          })
          .margin({ right: 2, bottom: PageLayoutSpec.contentEnd(this.bottomInset) / 2 })
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
