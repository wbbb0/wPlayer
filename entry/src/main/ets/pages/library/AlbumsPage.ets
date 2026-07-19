import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageGridBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryAlphabetIndex } from '../../components/library/LibraryAlphabetIndex';
import { LibraryEmptyState } from '../../components/library/LibraryEmptyState';
import {
  AlbumAction,
  AlbumGridItem,
  AlbumGridItemPlaceholder
} from '../../components/library/AlbumGridItem';
import {
  AlbumListItem,
  LibraryIndexPresentation,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import { LibrarySlot } from '../../library/store/PagedLibraryDataSource';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import { playbackRuntime } from '../../playback/PlaybackRuntime';

@Component
export struct AlbumsPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State selectedSectionIndex: number = 0;
  @State selectedAlbums: Array<AlbumListItem> = [];
  @State selectionBusy: boolean = false;
  scroller: Scroller = new Scroller();
  onOpenAlbum: (item: AlbumListItem) => void = (_item: AlbumListItem): void => {};
  onAlbumAction: (item: AlbumListItem, action: AlbumAction) => void =
    (_item: AlbumListItem, _action: AlbumAction): void => {};
  onNavigateAlbumAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  private readonly scrollBehavior: PageGridBehavior = new PageGridBehavior();

  aboutToAppear(): void {
    this.selection.deleteEnabled = false;
    this.selection.onPlay = (): void => this.runSelection((tracks: Array<TrackListItem>): void => {
      playbackRuntime.playInOrder(tracks[0], tracks);
      this.selection.cancel();
    });
    this.selection.onAddToPlaylist = (): void =>
      this.runSelection(this.onRequestAddToPlaylist);
    this.selection.onInsertNext = (): void => this.runSelection(
      (tracks: Array<TrackListItem>): void => playbackRuntime.insertNext(tracks)
    );
    this.selection.onAppendToQueue = (): void => this.runSelection(
      (tracks: Array<TrackListItem>): void => playbackRuntime.appendToQueue(tracks)
    );
  }

  private currentSelection(): Array<AlbumListItem> {
    return this.selectedAlbums.filter((album: AlbumListItem): boolean =>
      this.selection.isSelected(album.id));
  }

  private toggleSelection(album: AlbumListItem): void {
    this.selection.toggle(album.id);
    if (!this.selection.isSelected(album.id)) {
      this.selectedAlbums =
        this.selectedAlbums.filter((selected: AlbumListItem): boolean => selected.id !== album.id);
    } else {
      this.selectedAlbums =
        this.selectedAlbums.filter((selected: AlbumListItem): boolean => selected.id !== album.id)
          .concat([album]);
    }
  }

  private async selectedTracks(): Promise<Array<TrackListItem>> {
    const tracks: Array<TrackListItem> = [];
    const albums = this.currentSelection();
    for (let index = 0; index < albums.length; index += 1) {
      const detail = await this.store.getAlbumDetail(albums[index].id);
      if (detail !== undefined) {
        detail.tracks.forEach((track: TrackListItem): void => {
          if (!tracks.some((existing: TrackListItem): boolean => existing.id === track.id)) {
            tracks.push(track);
          }
        });
      }
    }
    return tracks;
  }

  private runSelection(action: (tracks: Array<TrackListItem>) => void, close: boolean = false): void {
    if (this.selectionBusy || this.selection.selectedCount() === 0) {
      return;
    }
    this.selectionBusy = true;
    this.selection.setBusy(true);
    this.selectedTracks().then((tracks: Array<TrackListItem>): void => {
      if (tracks.length > 0) {
        action(tracks);
      }
      if (close) {
        this.selectedAlbums = [];
        this.selection.cancel();
      }
    }).finally((): void => {
      this.selectionBusy = false;
      this.selection.setBusy(false);
    });
  }

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
                  actionsEnabled: true,
                  actionAnchorPrefix: 'albums',
                  selectionMode: this.selection.active,
                  selected: this.selection.isSelected(slot.value.id),
                  onActivate: this.onOpenAlbum,
                  onToggleSelection: (album: AlbumListItem): void => this.toggleSelection(album),
                  onAction: this.onAlbumAction,
                  onNavigate: this.onNavigateAlbumAction
                })
                  .reuseId('albums_actions')
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

  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
}
