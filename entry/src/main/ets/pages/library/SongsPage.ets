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
import {
  LibraryTrackRow,
  LibraryTrackRowVariant
} from '../../components/library/LibraryTrackRow';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import { playbackRuntime } from '../../playback/PlaybackRuntime';

@Component
export struct SongsPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State selectedSectionIndex: number = 0;
  @State selectedItems: Array<TrackListItem> = [];
  onPlayTrack: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  onOpenTrackActions: (item: TrackListItem, anchorId: string) => void =
    (_item: TrackListItem, _anchorId: string): void => {};
  onNavigateTrackAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageListBehavior =
    new PageListBehavior(LibraryPagingPolicy.TRACK_PAGE_SIZE);

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
          LazyForEach(this.store.trackDataSource, (track: TrackListItem, index: number) => {
            ListItem() {
              Column() {
                Divider()
                  .color($r('app.color.text_tertiary'))
                  .opacity(index > 0 ? 0.3 : 0)
                  .margin({ left: 80, right: PageLayoutSpec.HORIZONTAL_INSET })
                LibraryTrackRow({
                  track: track,
                  store: this.store,
                  variant: LibraryTrackRowVariant.LIBRARY,
                  artworkPath: track.smallArtworkPath.length > 0 ?
                    this.store.resolveArtworkPath(track.smallArtworkPath) : '',
                  actionAnchorPrefix: 'songs',
                  menuPlacement: Placement.BottomLeft,
                  horizontalInset: 16,
                  verticalInset: 8,
                  artworkSize: 52,
                  artworkCornerRadius: 10,
                  selectionMode: this.selection.active,
                  selected: this.selection.isSelected(track.id),
                  onActivate: this.onPlayTrack,
                  onOpenActions: this.onOpenTrackActions,
                  onOpenDetails: this.onOpenTrackDetails,
                  onNavigateAction: this.onNavigateTrackAction,
                  onRequestAddToPlaylist: this.onRequestAddToPlaylist,
                  onToggleSelection: (item: TrackListItem): void => this.toggleSelection(item)
                })
                  .height(68)
                  .reuseId(this.selection.active ? 'songs_library_selection' : 'songs_library_actions')
              }
              .width('100%')
            }
            .height(69)
          }, (track: TrackListItem) => `${track.id}`)
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
        .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
        .scrollBar(this.store.trackIndexPresentation === LibraryIndexPresentation.ALPHABET ?
          BarState.Off : BarState.Auto)
        .onScrollIndex((firstIndex: number, _lastIndex: number, _centerIndex: number) => {
          if (firstIndex < 0) {
            return;
          }
          const sectionIndex = LibraryPagingPolicy.selectedSectionIndex(this.store.trackSections, firstIndex);
          if (sectionIndex >= 0 && sectionIndex !== this.selectedSectionIndex) {
            this.selectedSectionIndex = sectionIndex;
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
