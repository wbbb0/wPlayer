import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageGridBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryAlphabetIndex } from '../../components/library/LibraryAlphabetIndex';
import { LibraryEmptyState } from '../../components/library/LibraryEmptyState';
import { ArtworkFitMode, ArtworkView } from '../../components/artwork/ArtworkView';
import {
  AlbumListItem,
  LibraryIndexPresentation
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import { LibrarySlot } from '../../library/store/PagedLibraryDataSource';

@Component
export struct AlbumsPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State selectedSectionIndex: number = 0;
  scroller: Scroller = new Scroller();
  onOpenAlbum: (item: AlbumListItem) => void = (_item: AlbumListItem): void => {};
  private readonly scrollBehavior: PageGridBehavior = new PageGridBehavior();

  build() {
    if (this.store.statistics.albumCount === 0) {
      LibraryEmptyState({
        symbol: $r('sys.symbol.opticaldisc'),
        title: '还没有专辑',
        description: '添加音乐后，专辑会显示在这里',
        loading: this.store.loading,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller
      })
    } else {
      Column() {
        Stack({ alignContent: Alignment.End }) {
        Grid(this.scroller) {
          LazyForEach(this.store.albumDataSource, (slot: LibrarySlot<AlbumListItem>) => {
            if (slot.value !== undefined) {
              GridItem() {
                Column({ space: 7 }) {
                  ArtworkView({
                    sourcePath: slot.value.artworkPath.length > 0 ?
                      this.store.resolveArtworkPath(slot.value.artworkPath) : '',
                    sourceWidth: slot.value.artworkWidth,
                    sourceHeight: slot.value.artworkHeight,
                    fitMode: ArtworkFitMode.CONTAIN,
                    cornerRadius: 18,
                    shadowEnabled: slot.value.artworkPath.length > 0
                  })
                  Text(slot.value.title)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .width('100%')
                  Text(slot.value.albumArtistDisplay.length > 0 ?
                    slot.value.albumArtistDisplay : `${slot.value.trackCount} 首`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                    .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .onClick(() => {
                  if (slot.value !== undefined) {
                    this.onOpenAlbum(slot.value);
                  }
                })
              }
            } else {
              GridItem() {
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
                .alignItems(HorizontalAlign.Start)
              }
            }
          }, (slot: LibrarySlot<AlbumListItem>) =>
            `${slot.generation}:${slot.index}:${slot.revision}`)
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
        .onScrollIndex((firstIndex: number, lastIndex: number) => {
          if (firstIndex < 0) {
            return;
          }
          const sectionIndex = LibraryPagingPolicy.selectedSectionIndex(this.store.albumSections, firstIndex);
          if (sectionIndex >= 0 && sectionIndex !== this.selectedSectionIndex) {
            this.selectedSectionIndex = sectionIndex;
          }
          this.store.ensureAlbumRange(firstIndex, lastIndex);
        })
        .attributeModifier(this.scrollBehavior)

        if (this.store.albumIndexPresentation === LibraryIndexPresentation.ALPHABET &&
          this.store.albumSections.length > 0) {
          LibraryAlphabetIndex({
            sections: this.store.albumSections,
            selectedIndex: this.selectedSectionIndex,
            onSelect: (itemIndex: number, sectionIndex: number) => {
              this.selectedSectionIndex = sectionIndex;
              this.scroller.scrollToIndex(itemIndex, false, ScrollAlign.START);
              this.store.ensureAlbumRange(itemIndex, itemIndex);
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
      .backgroundColor(Color.Transparent)
    }
  }
}
