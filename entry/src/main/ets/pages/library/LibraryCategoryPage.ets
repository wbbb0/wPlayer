import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryAlphabetIndex } from '../../components/library/LibraryAlphabetIndex';
import { LibraryCategoryRow } from '../../components/library/LibraryCategoryRow';
import { LibraryEmptyState } from '../../components/library/LibraryEmptyState';
import {
  LibraryCategoryKind,
  LibraryCategoryListItem
} from '../../library/model/LibraryModels';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import { LibrarySlot } from '../../library/store/PagedLibraryDataSource';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct LibraryCategoryPage {
  @ObjectLink store: LibraryStore;
  @Prop kind: LibraryCategoryKind = LibraryCategoryKind.ARTIST;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State selectedSectionIndex: number = 0;
  scroller: Scroller = new Scroller();
  onOpenCategory: (item: LibraryCategoryListItem) => void =
    (_item: LibraryCategoryListItem): void => {};
  private readonly scrollBehavior: PageListBehavior =
    new PageListBehavior(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT);

  private emptyTitle(): string {
    return this.kind === LibraryCategoryKind.ARTIST ? '还没有艺人' : '还没有流派';
  }

  private emptyDescription(): string {
    return this.kind === LibraryCategoryKind.ARTIST ?
      '导入包含艺人信息的音乐后会显示在这里' : '导入包含流派信息的音乐后会显示在这里';
  }

  private alphabetIndexVisible(): boolean {
    return this.store.categorySections(this.kind).length > 0;
  }

  build() {
    if (this.store.categoryCount(this.kind) === 0) {
      LibraryEmptyState({
        symbol: this.kind === LibraryCategoryKind.ARTIST ?
          $r('sys.symbol.person_2_fill') : $r('sys.symbol.music_note_list_fill'),
        title: this.emptyTitle(),
        description: this.emptyDescription(),
        loading: this.store.loading,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller
      })
    } else {
      Stack({ alignContent: Alignment.End }) {
        List({ space: 0, scroller: this.scroller }) {
          LazyForEach(this.store.categoryDataSource(this.kind),
            (slot: LibrarySlot<LibraryCategoryListItem>) => {
            ListItem() {
              Column() {
                Divider()
                  .color($r('app.color.text_tertiary'))
                  .opacity(slot.index > 0 ? 0.3 : 0)
                  .margin({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET })
                if (slot.value !== undefined) {
                  LibraryCategoryRow({
                    item: slot.value,
                    horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
                    verticalInset: 8,
                    onActivate: this.onOpenCategory
                  })
                    .height(68)
                    .reuseId(this.kind === LibraryCategoryKind.ARTIST ? 'artist_text_row' : 'genre_text_row')
                } else {
                  Column({ space: 6 }) {
                    Row().width(144).height(16).backgroundColor($r('app.color.text_tertiary')).opacity(0.16)
                    Row().width(92).height(12).backgroundColor($r('app.color.text_tertiary')).opacity(0.1)
                  }
                  .width('100%')
                  .height(68)
                  .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET })
                  .alignItems(HorizontalAlign.Start)
                  .justifyContent(FlexAlign.Center)
                }
              }
              .width('100%')
            }
            .height(69)
          }, (slot: LibrarySlot<LibraryCategoryListItem>) => slot.key)
        }
        .width('100%')
        .height('100%')
        .padding({ right: LibraryAlphabetIndex.contentGutter(this.alphabetIndexVisible()) })
        .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
        .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
        .scrollBar(this.alphabetIndexVisible() ? BarState.Off : BarState.Auto)
        .attributeModifier(this.scrollBehavior)
        .onScrollIndex((firstIndex: number, lastIndex: number, _centerIndex: number): void => {
          if (firstIndex < 0) {
            return;
          }
          const sectionIndex = LibraryPagingPolicy.selectedSectionIndex(
            this.store.categorySections(this.kind), firstIndex
          );
          if (sectionIndex >= 0 && sectionIndex !== this.selectedSectionIndex) {
            this.selectedSectionIndex = sectionIndex;
          }
          this.store.ensureCategoryRange(this.kind, firstIndex, lastIndex);
        })

        if (this.alphabetIndexVisible()) {
          LibraryAlphabetIndex({
            sections: this.store.categorySections(this.kind),
            selectedIndex: this.selectedSectionIndex,
            onSelect: (itemIndex: number, sectionIndex: number): void => {
              this.selectedSectionIndex = sectionIndex;
              this.store.ensureCategoryRange(this.kind, itemIndex, itemIndex);
              this.scroller.scrollToIndex(itemIndex, false, ScrollAlign.START);
            }
          })
          .margin({
            right: LibraryAlphabetIndex.RIGHT_MARGIN,
            bottom: PageLayoutSpec.contentEnd(this.bottomInset) / 2
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
  }
}
