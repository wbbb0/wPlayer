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
  LibraryTrackRow,
  LibraryTrackRowVariant
} from '../../components/library/LibraryTrackRow';
import { LibraryTrackRowPlaceholder } from '../../components/library/LibraryTrackRowPlaceholder';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import {
  DragSelectionController,
  DragSelectionHitMode
} from '../../components/library/DragSelectionController';
import { playbackRuntime } from '../../playback/PlaybackRuntime';

@Component
export struct SongsPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State selectedSectionIndex: number = 0;
  @State selectedItems: Array<TrackListItem> = [];
  @State selectionDragActive: boolean = false;
  onPlayTrack: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  onOpenTrackActions: (item: TrackListItem, anchorId: string) => void =
    (_item: TrackListItem, _anchorId: string): void => {};
  onNavigateTrackAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  scroller: Scroller = new Scroller();
  private readonly dragSelection: DragSelectionController = new DragSelectionController(
    (ids: Array<number>, selected: boolean): void => this.selection.previewSelection(ids, selected),
    (active: boolean): void => { this.selectionDragActive = active; }
  );
  private readonly scrollBehavior: PageListBehavior =
    new PageListBehavior(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT);

  aboutToAppear(): void {
    this.selection.deleteEnabled = false;
    this.selection.onPlay = (): void => this.playSelection();
    this.selection.onAddToPlaylist = (): void =>
      this.onRequestAddToPlaylist(this.currentSelection());
    this.selection.onInsertNext = (): void => playbackRuntime.insertNext(this.currentSelection());
    this.selection.onAppendToQueue = (): void =>
      playbackRuntime.appendToQueue(this.currentSelection());
    this.selection.selectableCount = this.store.statistics.trackCount;
    this.selection.onToggleAll = (): void => this.toggleAll();
  }

  aboutToDisappear(): void {
    this.dragSelection.end();
  }

  private toggleAll(): void {
    if (this.selection.allSelected()) {
      this.selectedItems = [];
      this.selection.replaceSelection([]);
      return;
    }
    this.selection.setBusy(true);
    this.store.loadTrackPlaybackOrder().then((items: Array<TrackListItem>): void => {
      this.selectedItems = items;
      this.selection.selectableCount = items.length;
      this.selection.replaceSelection(items.map((item: TrackListItem): number => item.id));
    }).catch((error: Object): void => {
      console.warn(`Unable to select all tracks: ${error}`);
    }).finally((): void => this.selection.setBusy(false));
  }

  private currentSelection(): Array<TrackListItem> {
    return this.selectedItems.filter((item: TrackListItem): boolean =>
      this.selection.isSelected(item.id));
  }

  private toggleSelection(item: TrackListItem): void {
    this.setSelection(item, !this.selection.isSelected(item.id));
  }

  private setSelection(item: TrackListItem, selected: boolean): void {
    this.selection.setSelected(item.id, selected);
    if (!selected) {
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

  private alphabetIndexVisible(): boolean {
    return this.store.trackIndexPresentation === LibraryIndexPresentation.ALPHABET &&
      this.store.trackSections.length > 0;
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
            ListItem() {
              Column() {
                Divider()
                  .color($r('app.color.text_tertiary'))
                  .opacity(slot.index > 0 ? 0.3 : 0)
                  .margin({ left: 80, right: PageLayoutSpec.HORIZONTAL_INSET })
                if (slot.value !== undefined) {
                  LibraryTrackRow({
                    track: slot.value,
                    store: this.store,
                    variant: LibraryTrackRowVariant.LIBRARY,
                    artworkPath: slot.value.smallArtworkPath.length > 0 ?
                      this.store.resolveArtworkPath(slot.value.smallArtworkPath) : '',
                    actionAnchorPrefix: 'songs',
                    menuPlacement: Placement.BottomLeft,
                    horizontalInset: 16,
                    verticalInset: 8,
                    artworkSize: 52,
                    artworkCornerRadius: 10,
                    selectionMode: this.selection.active,
                    selected: this.selection.isPresentedSelected(slot.value.id),
                    onActivate: this.onPlayTrack,
                    onOpenActions: this.onOpenTrackActions,
                    onOpenDetails: this.onOpenTrackDetails,
                    onShareTrackFile: this.onShareTrackFile,
                    onNavigateAction: this.onNavigateTrackAction,
                    onRequestAddToPlaylist: this.onRequestAddToPlaylist,
                    onToggleSelection: (item: TrackListItem): void => this.toggleSelection(item),
                    onSelectionTargetAreaChange: (item: TrackListItem, area: Area): void =>
                      this.dragSelection.updateTarget(item.id, item.id, slot.index, area,
                        DragSelectionHitMode.ROW,
                        (): boolean => this.selection.isSelected(item.id),
                        (selected: boolean): void => this.setSelection(item, selected)),
                    onSelectionTargetRemoved: (id: number): void => this.dragSelection.removeTarget(id),
                    onSelectionDragStart: (item: TrackListItem, _x: number, _y: number): void =>
                      this.dragSelection.start(item.id),
                    onSelectionDragUpdate: (x: number, y: number): void =>
                      this.dragSelection.update(x, y),
                    onSelectionDragEnd: (): void => this.dragSelection.end(),
                    onSelectionDragCancel: (): void => this.dragSelection.cancel()
                  })
                    .height(68)
                    .reuseId('songs_library')
                } else {
                  LibraryTrackRowPlaceholder({
                    horizontalInset: 16,
                    verticalInset: 8,
                    artworkSize: 52,
                    artworkCornerRadius: 10,
                    selectionMode: this.selection.active
                  })
                    .height(68)
                }
              }
              .width('100%')
            }
            .height(69)
          }, (slot: LibrarySlot<TrackListItem>) => slot.key)
        }
        .width('100%')
        .height('100%')
        .padding({ right: LibraryAlphabetIndex.contentGutter(this.alphabetIndexVisible()) })
        .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
        .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
        .scrollBar(this.store.trackIndexPresentation === LibraryIndexPresentation.ALPHABET ?
          BarState.Off : BarState.Auto)
        .enableScrollInteraction(!this.selectionDragActive)
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
        .attributeModifier(this.scrollBehavior)

        if (this.alphabetIndexVisible()) {
          LibraryAlphabetIndex({
            sections: this.store.trackSections,
            selectedIndex: this.selectedSectionIndex,
            onSelect: (itemIndex: number, sectionIndex: number) => {
              this.selectedSectionIndex = sectionIndex;
              this.store.ensureTrackRange(itemIndex, itemIndex);
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
