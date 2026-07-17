import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageGridBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryAlphabetIndex } from '../../components/library/LibraryAlphabetIndex';
import { LibraryEmptyState } from '../../components/library/LibraryEmptyState';
import { AlbumGridItem, AlbumGridItemPlaceholder } from '../../components/library/AlbumGridItem';
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
                AlbumGridItem({
                  store: this.store,
                  album: slot.value,
                  onActivate: this.onOpenAlbum
                })
              }
            } else {
              GridItem() {
                AlbumGridItemPlaceholder()
              }
            }
          }, (slot: LibrarySlot<AlbumListItem>) =>
            `${slot.generation}:${slot.index}:${slot.revision}`)
        }
        .columnsTemplate(PageLayoutSpec.albumColumnsTemplate())
        .columnsGap(PageLayoutSpec.ALBUM_COLUMN_GAP)
        .rowsGap(PageLayoutSpec.ALBUM_ROW_GAP)
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
