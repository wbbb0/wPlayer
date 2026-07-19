import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryAlphabetIndex } from '../../components/library/LibraryAlphabetIndex';
import { LibraryEmptyState } from '../../components/library/LibraryEmptyState';
import {
  LibraryIndexPresentation,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import { LibrarySlot } from '../../library/store/PagedLibraryDataSource';
import {
  SongListItem,
  SongListItemLayout,
  SongListItemLayoutSpec
} from '../../components/library/SongListItem';
import { LayoutLength } from '../../components/layout/LayoutLength';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import { playbackRuntime } from '../../playback/PlaybackRuntime';

@Component
export struct SongsPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State selectedSectionIndex: number = 0;
  @State listWidth: number = 0;
  @State selectedItems: Array<TrackListItem> = [];
  onPlayTrack: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  onOpenTrackActions: (item: TrackListItem, anchorId: string) => void =
    (_item: TrackListItem, _anchorId: string): void => {};
  onNavigateTrackAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageListBehavior =
    new PageListBehavior(PageLayoutSpec.SONG_LIST_CACHE_COUNT);

  private contextPreviewWidth(): number {
    return Math.max(
      SongListItemLayoutSpec.CONTEXT_PREVIEW_FALLBACK_WIDTH,
      this.listWidth - SongListItemLayoutSpec.LIBRARY_PREVIEW_TRAILING_RESERVE
    );
  }

  aboutToAppear(): void {
    this.selection.deleteEnabled = false;
    this.selection.onPlay = (): void => this.playSelection();
    this.selection.onAddToPlaylist = (): void =>
      this.onRequestAddToPlaylist(this.currentSelection());
    this.selection.onInsertNext = (): void => playbackRuntime.insertNext(this.currentSelection());
    this.selection.onAppendToQueue = (): void =>
      playbackRuntime.appendToQueue(this.currentSelection());
  }

  private currentSelection(): Array<TrackListItem> {
    return this.selectedItems.filter((item: TrackListItem): boolean =>
      this.selection.isSelected(item.id));
  }

  private toggleSelection(item: TrackListItem): void {
    this.selection.toggle(item.id);
    if (!this.selection.isSelected(item.id)) {
      this.selectedItems =
        this.selectedItems.filter((selected: TrackListItem): boolean => selected.id !== item.id);
    } else {
      this.selectedItems =
        this.selectedItems.filter((selected: TrackListItem): boolean => selected.id !== item.id)
          .concat([item]);
    }
  }

  private playSelection(): void {
    const items = this.currentSelection();
    if (items.length > 0) {
      playbackRuntime.playInOrder(items[0], items);
      this.selectedItems = [];
      this.selection.cancel();
    }
  }

  build() {
    if (this.store.statistics.trackCount === 0) {
      LibraryEmptyState({
        symbol: $r('sys.symbol.music_fill'),
        title: '还没有音乐',
        description: '可在“更多 → 音乐库”中添加 MP3 或 FLAC',
        loading: this.store.loading,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller
      })
    } else {
      Stack({ alignContent: Alignment.End }) {
        List({ space: 0, scroller: this.scroller }) {
          LazyForEach(this.store.trackDataSource, (slot: LibrarySlot<TrackListItem>) => {
            if (slot.value !== undefined) {
              ListItem() {
                Column() {
                  if (slot.index > 0) {
                    Divider()
                      .color($r('app.color.text_tertiary'))
                      .opacity(0.3)
                      .margin({ left: 80, right: PageLayoutSpec.HORIZONTAL_INSET })
                  }
                  SongListItem({
                    item: slot.value,
                    libraryStore: this.store,
                    layout: SongListItemLayout.LIBRARY,
                    artworkPath: slot.value.smallArtworkPath.length > 0 ?
                      this.store.resolveArtworkPath(slot.value.smallArtworkPath) : '',
                    actionTrack: slot.value,
                    actionAnchorPrefix: 'songs',
                    menuPlacement: Placement.BottomLeft,
                    horizontalInset: 16,
                    verticalInset: 8,
                    artworkSize: 52,
                    artworkCornerRadius: 10,
                    contextPreviewWidth: this.contextPreviewWidth(),
                    selectionMode: this.selection.active,
                    selected: this.selection.isSelected(slot.value.id),
                    onActivate: (): void => {
                      if (slot.value !== undefined) {
                        this.onPlayTrack(slot.value);
                      }
                    },
                    onOpenActions: this.onOpenTrackActions,
                    onNavigateAction: this.onNavigateTrackAction,
                    onRequestAddToPlaylist: this.onRequestAddToPlaylist
                    ,
                    onToggleSelection: (): void => this.toggleSelection(slot.value!)
                  })
                    .reuseId('songs_library')
                }
                .width('100%')
              }
            } else {
              ListItem() {
                Column() {
                  if (slot.index > 0) {
                    Divider()
                      .color($r('app.color.text_tertiary'))
                      .opacity(0.3)
                      .margin({ left: 80, right: PageLayoutSpec.HORIZONTAL_INSET })
                  }
                  Row({ space: 12 }) {
                    Row()
                      .width(52)
                      .height(52)
                      .borderRadius(10)
                      .backgroundColor($r('app.color.text_tertiary'))
                      .opacity(0.12)
                    Column({ space: 8 }) {
                      Row()
                        .width('58%')
                        .height(12)
                        .borderRadius(6)
                        .backgroundColor($r('app.color.text_tertiary'))
                        .opacity(0.14)
                      Row()
                        .width('38%')
                        .height(10)
                        .borderRadius(5)
                        .backgroundColor($r('app.color.text_tertiary'))
                        .opacity(0.1)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Row()
                      .width(38)
                      .height(38)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                }
                .width('100%')
              }
            }
          }, (slot: LibrarySlot<TrackListItem>) =>
            `${slot.generation}:${slot.index}:${slot.revision}`)
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
        .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
        .scrollBar(this.store.trackIndexPresentation === LibraryIndexPresentation.ALPHABET ?
          BarState.Off : BarState.Auto)
        .onScrollIndex((firstIndex: number, lastIndex: number, _centerIndex: number) => {
          if (firstIndex < 0) {
            return;
          }
          const sectionIndex = LibraryPagingPolicy.selectedSectionIndex(this.store.trackSections, firstIndex);
          if (sectionIndex >= 0 && sectionIndex !== this.selectedSectionIndex) {
            this.selectedSectionIndex = sectionIndex;
          }
          this.store.ensureTrackRange(firstIndex, lastIndex);
        })
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          const nextWidth = LayoutLength.toNumber(newValue.width, this.listWidth);
          if (nextWidth > 0 && Math.abs(nextWidth - this.listWidth) >= 0.5) {
            this.listWidth = nextWidth;
          }
        })
        .attributeModifier(this.scrollBehavior)

        if (this.store.trackIndexPresentation === LibraryIndexPresentation.ALPHABET &&
          this.store.trackSections.length > 0) {
          LibraryAlphabetIndex({
            sections: this.store.trackSections,
            selectedIndex: this.selectedSectionIndex,
            onSelect: (itemIndex: number, sectionIndex: number) => {
              this.selectedSectionIndex = sectionIndex;
              this.scroller.scrollToIndex(itemIndex, false, ScrollAlign.START);
              this.store.ensureTrackRange(itemIndex, itemIndex);
            }
          })
          .margin({ right: 2, bottom: PageLayoutSpec.contentEnd(this.bottomInset) / 2 })
        }

      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
    }
  }
}
