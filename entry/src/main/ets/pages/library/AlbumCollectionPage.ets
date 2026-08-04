import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageGridBehavior } from '../../components/layout/PageScrollBehavior';
import { AlbumAction, AlbumGridItem } from '../../components/library/AlbumGridItem';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import { AlbumListItem, LibraryNavigationTarget, TrackListItem } from '../../library/model/LibraryModels';
import { AlbumCollectionState } from '../../library/store/LibraryCollectionState';
import { LibrarySlot } from '../../library/store/PagedLibraryDataSource';
import { LibraryStore } from '../../library/store/LibraryStore';
import { LayoutLength } from '../../components/layout/LayoutLength';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import {
  DragSelectionController,
  DragSelectionHitMode
} from '../../components/library/DragSelectionController';

@Component
export struct AlbumCollectionPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink state: AlbumCollectionState;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State gridWidth: number = 0;
  @State selectedAlbums: Array<AlbumListItem> = [];
  @State selectionBusy: boolean = false;
  @State selectionDragActive: boolean = false;
  scroller: Scroller = new Scroller();
  private readonly dragSelection: DragSelectionController = new DragSelectionController(
    (ids: Array<number>, selected: boolean): void => this.selection.previewSelection(ids, selected),
    (active: boolean): void => { this.selectionDragActive = active; }
  );
  onOpenAlbum: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onAlbumAction: (album: AlbumListItem, action: AlbumAction) => void =
    (_album: AlbumListItem, _action: AlbumAction): void => {};
  onNavigate: (target: LibraryNavigationTarget) => void = (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  private readonly scrollBehavior: PageGridBehavior = new PageGridBehavior();

  aboutToAppear(): void {
    this.state.activate(this.store);
    this.selection.deleteEnabled = false;
    this.selection.selectableCount = this.state.totalCount;
    this.selection.onToggleAll = (): void => this.toggleAll();
    this.selection.onPlay = (): void => this.runSelection((tracks: Array<TrackListItem>): void => {
      playbackRuntime.playInOrder(tracks[0], tracks);
      this.selection.cancel();
    });
    this.selection.onAddToPlaylist = (): void => this.runSelection(this.onRequestAddToPlaylist);
    this.selection.onInsertNext = (): void =>
      this.runSelection((tracks: Array<TrackListItem>): void => playbackRuntime.insertNext(tracks));
    this.selection.onAppendToQueue = (): void =>
      this.runSelection((tracks: Array<TrackListItem>): void => playbackRuntime.appendToQueue(tracks));
  }

  aboutToDisappear(): void {
    this.dragSelection.end();
    this.state.deactivate(this.store);
  }

  private toggleAll(): void {
    if (this.selection.allSelected()) {
      this.selectedAlbums = [];
      this.selection.replaceSelection([]);
      return;
    }
    this.selection.setBusy(true);
    this.state.loadSnapshot(this.store).then((albums: Array<AlbumListItem>): void => {
      this.selectedAlbums = albums;
      this.selection.selectableCount = albums.length;
      this.selection.replaceSelection(albums.map((album: AlbumListItem): number => album.id));
    }).catch((error: Object): void => console.warn(`Unable to select albums: ${error}`))
      .finally((): void => this.selection.setBusy(false));
  }

  private toggleSelection(album: AlbumListItem): void {
    this.setSelection(album, !this.selection.isSelected(album.id));
  }

  private setSelection(album: AlbumListItem, selected: boolean): void {
    this.selection.setSelected(album.id, selected);
    this.selectedAlbums = this.selectedAlbums.filter((item: AlbumListItem): boolean => item.id !== album.id);
    if (selected) {
      this.selectedAlbums = this.selectedAlbums.concat([album]);
    }
  }

  private currentSelection(): Array<AlbumListItem> {
    return this.selectedAlbums.filter((album: AlbumListItem): boolean => this.selection.isSelected(album.id));
  }

  private async selectedTracks(): Promise<Array<TrackListItem>> {
    const tracks: Array<TrackListItem> = [];
    const albums = this.currentSelection();
    for (let index = 0; index < albums.length; index += 1) {
      const albumTracks = await this.store.getAlbumTracks(albums[index].id);
      albumTracks.forEach((track: TrackListItem): void => {
        if (!tracks.some((existing: TrackListItem): boolean => existing.id === track.id)) {
          tracks.push(track);
        }
      });
    }
    return tracks;
  }

  private runSelection(action: (tracks: Array<TrackListItem>) => void): void {
    if (this.selectionBusy || this.selection.selectedCount() === 0) {
      return;
    }
    this.selectionBusy = true;
    this.selection.setBusy(true);
    this.selectedTracks().then((tracks: Array<TrackListItem>): void => {
      if (tracks.length > 0) {
        action(tracks);
      }
    }).catch((error: Object): void => {
      console.warn(`Unable to load selected album tracks: ${error}`);
    }).finally((): void => {
      this.selectionBusy = false;
      this.selection.setBusy(false);
    });
  }

  build() {
    Grid(this.scroller, { regularSize: [1, 1] }) {
      LazyForEach(this.state.dataSource, (slot: LibrarySlot<AlbumListItem>) => {
        GridItem() {
          if (slot.value !== undefined) {
            AlbumGridItem({
              store: this.store,
              album: slot.value,
              actionsEnabled: true,
              artworkShadowEnabled: false,
              selectionMode: this.selection.active,
              selected: this.selection.isPresentedSelected(slot.value.id),
              onActivate: this.onOpenAlbum,
              onToggleSelection: (album: AlbumListItem): void => this.toggleSelection(album),
              onSelectionTargetAreaChange: (album: AlbumListItem, area: Area): void =>
                this.dragSelection.updateTarget(album.id, album.id, slot.index, area,
                  DragSelectionHitMode.RECTANGLE,
                  (): boolean => this.selection.isSelected(album.id),
                  (selected: boolean): void => this.setSelection(album, selected)),
              onSelectionTargetRemoved: (id: number): void => this.dragSelection.removeTarget(id),
              onSelectionDragStart: (album: AlbumListItem, _x: number, _y: number): void =>
                this.dragSelection.start(album.id),
              onSelectionDragUpdate: (x: number, y: number): void =>
                this.dragSelection.update(x, y),
              onSelectionDragEnd: (): void => this.dragSelection.end(),
              onSelectionDragCancel: (): void => this.dragSelection.cancel(),
              onAction: this.onAlbumAction,
              onNavigate: this.onNavigate
            }).reuseId('album_collection')
          } else {
            Column({ space: 7 }) {
              Row().width('100%').aspectRatio(1).borderRadius(18)
                .backgroundColor($r('app.color.text_tertiary')).opacity(0.12)
              Row().width('72%').height(12).borderRadius(6)
                .backgroundColor($r('app.color.text_tertiary')).opacity(0.14)
              Row().width('46%').height(10).borderRadius(5)
                .backgroundColor($r('app.color.text_tertiary')).opacity(0.1)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }
        }
      }, (slot: LibrarySlot<AlbumListItem>) => slot.key)
    }
    .columnsTemplate(PageLayoutSpec.albumColumnsTemplate(this.gridWidth, PageLayoutSpec.HORIZONTAL_INSET))
    .columnsGap(PageLayoutSpec.ALBUM_COLUMN_GAP).rowsGap(PageLayoutSpec.ALBUM_ROW_GAP)
    .width('100%').height('100%')
    .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET })
    .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
    .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
    .attributeModifier(this.scrollBehavior)
    .onScrollIndex((firstIndex: number, lastIndex: number): void => {
      this.state.ensureRange(firstIndex, lastIndex).catch((error: Object): void =>
        console.warn(`Unable to prefetch albums: ${error}`));
    })
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      const nextWidth = LayoutLength.toNumber(newValue.width, this.gridWidth);
      if (nextWidth > 0 && Math.abs(nextWidth - this.gridWidth) >= 0.5) {
        this.gridWidth = nextWidth;
      }
    })
    .enableScrollInteraction(!this.selectionDragActive)
  }
}
