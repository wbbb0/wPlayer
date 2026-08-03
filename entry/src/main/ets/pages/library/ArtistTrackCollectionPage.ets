import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryTrackRow, LibraryTrackRowVariant } from '../../components/library/LibraryTrackRow';
import { LibraryTrackRowPlaceholder } from '../../components/library/LibraryTrackRowPlaceholder';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import { LibraryNavigationTarget, TrackListItem } from '../../library/model/LibraryModels';
import { ArtistTrackCollectionState } from '../../library/store/LibraryCollectionState';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import { LibrarySlot } from '../../library/store/PagedLibraryDataSource';
import { LibraryStore } from '../../library/store/LibraryStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import {
  DragSelectionController,
  DragSelectionHitMode
} from '../../components/library/DragSelectionController';

@Component
export struct ArtistTrackCollectionPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink state: ArtistTrackCollectionState;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop actionAnchorPrefix: string = 'artist_tracks';
  @State selectionDragActive: boolean = false;
  scroller: Scroller = new Scroller();
  private readonly dragSelection: DragSelectionController = new DragSelectionController(
    (ids: Array<number>, selected: boolean): void => this.selection.previewSelection(ids, selected),
    (active: boolean): void => { this.selectionDragActive = active; }
  );
  @State selectedItems: Array<TrackListItem> = [];
  @State snapshotBusy: boolean = false;
  onOpenTrackActions: (track: TrackListItem, anchorId: string) => void =
    (_track: TrackListItem, _anchorId: string): void => {};
  onNavigateTrackAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  private readonly scrollBehavior: PageListBehavior =
    new PageListBehavior(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT);

  aboutToAppear(): void {
    this.state.activate(this.store);
    this.selection.deleteEnabled = false;
    this.selection.onPlay = (): void => this.playSelection();
    this.selection.onAddToPlaylist = (): void =>
      this.onRequestAddToPlaylist(this.currentSelection());
    this.selection.onInsertNext = (): void => playbackRuntime.insertNext(this.currentSelection());
    this.selection.onAppendToQueue = (): void => playbackRuntime.appendToQueue(this.currentSelection());
    this.selection.selectableCount = this.state.totalCount;
    this.selection.onToggleAll = (): void => this.toggleAll();
  }

  aboutToDisappear(): void {
    this.dragSelection.end();
    this.state.deactivate(this.store);
  }

  private toggleAll(): void {
    if (this.selection.allSelected()) {
      this.selectedItems = [];
      this.selection.replaceSelection([]);
      return;
    }
    this.selection.setBusy(true);
    this.state.loadSnapshot(this.store).then((tracks: Array<TrackListItem>): void => {
      this.selectedItems = tracks;
      this.selection.selectableCount = tracks.length;
      this.selection.replaceSelection(tracks.map((track: TrackListItem): number => track.id));
    }).catch((error: Object): void => console.warn(`Unable to select artist tracks: ${error}`))
      .finally((): void => this.selection.setBusy(false));
  }

  private toggleSelection(track: TrackListItem): void {
    this.setSelection(track, !this.selection.isSelected(track.id));
  }

  private setSelection(track: TrackListItem, selected: boolean): void {
    this.selection.setSelected(track.id, selected);
    this.selectedItems = this.selectedItems.filter((item: TrackListItem): boolean => item.id !== track.id);
    if (selected) {
      this.selectedItems = this.selectedItems.concat([track]);
    }
  }

  private currentSelection(): Array<TrackListItem> {
    return this.selectedItems.filter((item: TrackListItem): boolean => this.selection.isSelected(item.id));
  }

  private playSelection(): void {
    const items = this.currentSelection();
    if (items.length > 0) {
      playbackRuntime.playInOrder(items[0], items);
      this.selectedItems = [];
      this.selection.cancel();
    }
  }

  private playTrack(track: TrackListItem): void {
    if (this.snapshotBusy) {
      return;
    }
    this.snapshotBusy = true;
    this.state.loadSnapshot(this.store).then((tracks: Array<TrackListItem>): void => {
      const current = tracks.find((item: TrackListItem): boolean => item.id === track.id);
      if (current !== undefined) {
        playbackRuntime.playInOrder(current, tracks);
      }
    }).catch((error: Object): void => console.warn(`Unable to load artist tracks: ${error}`))
      .finally((): void => {
        this.snapshotBusy = false;
      });
  }

  build() {
    List({ space: 0, scroller: this.scroller }) {
      LazyForEach(this.state.dataSource, (slot: LibrarySlot<TrackListItem>) => {
        ListItem() {
          Column() {
            Divider().color($r('app.color.text_tertiary')).opacity(slot.index > 0 ? 0.3 : 0)
              .margin({ left: 80, right: PageLayoutSpec.HORIZONTAL_INSET })
            if (slot.value !== undefined) {
              LibraryTrackRow({
                track: slot.value,
                store: this.store,
                variant: LibraryTrackRowVariant.LIBRARY,
                artworkPath: slot.value.smallArtworkPath.length > 0 ?
                  this.store.resolveArtworkPath(slot.value.smallArtworkPath) : '',
                actionAnchorPrefix: this.actionAnchorPrefix,
                horizontalInset: 16,
                verticalInset: 8,
                artworkSize: 52,
                artworkCornerRadius: 10,
                selectionMode: this.selection.active,
                selected: this.selection.isPresentedSelected(slot.value.id),
                onActivate: (item: TrackListItem): void => this.playTrack(item),
                onOpenActions: this.onOpenTrackActions,
                onOpenDetails: this.onOpenTrackDetails,
                onShareTrackFile: this.onShareTrackFile,
                onNavigateAction: this.onNavigateTrackAction,
                onRequestAddToPlaylist: this.onRequestAddToPlaylist,
                onToggleSelection: (item: TrackListItem): void => this.toggleSelection(item),
                onSelectionTargetAreaChange: (item: TrackListItem, area: Area): void =>
                  this.dragSelection.updateTarget(item.id, slot.index, area,
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
              }).height(68).reuseId('artist_tracks')
            } else {
              LibraryTrackRowPlaceholder({ horizontalInset: 16, verticalInset: 8, artworkSize: 52,
                artworkCornerRadius: 10, selectionMode: this.selection.active }).height(68)
            }
          }.width('100%')
        }.height(69)
      }, (slot: LibrarySlot<TrackListItem>) => slot.key)
    }
    .width('100%').height('100%')
    .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
    .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
    .attributeModifier(this.scrollBehavior)
    .enableScrollInteraction(!this.selectionDragActive)
    .onScrollIndex((firstIndex: number, lastIndex: number): void => {
      this.state.ensureRange(firstIndex, lastIndex).catch((error: Object): void =>
        console.warn(`Unable to prefetch artist tracks: ${error}`));
    })
  }
}
