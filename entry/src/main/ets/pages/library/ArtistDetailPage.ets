import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { AlbumGridSection } from '../../components/library/AlbumGridItem';
import {
  LibraryTrackRow,
  LibraryTrackRowVariant
} from '../../components/library/LibraryTrackRow';
import {
  AlbumListItem,
  ArtistDetailOverview,
  LibraryEntityIdentity,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { ArtistDetailState } from '../../library/store/LibraryDetailState';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import { LibraryStore } from '../../library/store/LibraryStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import {
  LibrarySlot
} from '../../library/store/PagedLibraryDataSource';
import { LibraryTrackRowPlaceholder } from '../../components/library/LibraryTrackRowPlaceholder';
import {
  DetailTrackListPagingPolicy,
  DetailTrackVisibleRange
} from '../../library/store/DetailTrackListPagingPolicy';

@Component
export struct ArtistDetailPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink state: ArtistDetailState;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @Prop actionAnchorPrefix: string = 'artist';
  @Prop currentIdentity: LibraryEntityIdentity | undefined = undefined;
  @State selectedItems: Array<TrackListItem> = [];
  @State snapshotActionBusy: boolean = false;
  scroller: Scroller = new Scroller();
  onOpenAlbum: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onOpenTrackActions: (track: TrackListItem, anchorId: string) => void =
    (_track: TrackListItem, _anchorId: string): void => {};
  onNavigateTrackAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  private readonly scrollBehavior: PageListBehavior =
    new PageListBehavior(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT);

  aboutToAppear(): void {
    this.state.activate(this.store);
    this.selection.deleteEnabled = false;
    this.selection.onPlay = (): void => this.playSelection();
    this.selection.onAddToPlaylist = (): void =>
      this.onRequestAddToPlaylist(this.currentSelection());
    this.selection.onInsertNext = (): void => playbackRuntime.insertNext(this.currentSelection());
    this.selection.onAppendToQueue = (): void =>
      playbackRuntime.appendToQueue(this.currentSelection());
    this.selection.onToggleAll = (): void => this.toggleAll();
  }

  private toggleAll(): void {
    if (this.selection.allSelected()) {
      this.selectedItems = [];
      this.selection.replaceSelection([]);
      return;
    }
    this.selection.setBusy(true);
    this.state.loadTrackSnapshot(this.store).then((tracks: Array<TrackListItem>): void => {
      this.selectedItems = tracks;
      this.selection.selectableCount = tracks.length;
      this.selection.replaceSelection(tracks.map((track: TrackListItem): number => track.id));
    }).catch((error: Object): void => {
      console.warn(`Unable to select all artist tracks: ${error}`);
    }).finally((): void => this.selection.setBusy(false));
  }

  aboutToDisappear(): void {
    this.state.deactivate(this.store);
  }

  private durationLabel(durationMs: number): string {
    const totalMinutes = Math.max(0, Math.floor(durationMs / 60000));
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    return hours > 0 ? `${hours} 小时 ${minutes} 分钟` : `${minutes} 分钟`;
  }

  private runSnapshotAction(action: (tracks: Array<TrackListItem>) => void): void {
    if (this.snapshotActionBusy) {
      return;
    }
    this.snapshotActionBusy = true;
    this.state.loadTrackSnapshot(this.store).then((tracks: Array<TrackListItem>): void => {
      if (this.state.detail !== undefined && tracks.length > 0) {
        action(tracks);
      }
      this.snapshotActionBusy = false;
    }).catch((error: Object): void => {
      console.warn(`Unable to load artist playback order: ${error}`);
      this.snapshotActionBusy = false;
    });
  }

  private playTrack(track: TrackListItem): void {
    this.runSnapshotAction((tracks: Array<TrackListItem>): void => {
      const current = tracks.find((item: TrackListItem): boolean => item.id === track.id);
      if (current !== undefined) {
        playbackRuntime.playInOrder(current, tracks);
      }
    });
  }

  private currentSelection(): Array<TrackListItem> {
    return this.selectedItems.filter((item: TrackListItem): boolean =>
      this.selection.isSelected(item.id));
  }

  private toggleSelection(track: TrackListItem): void {
    this.selection.toggle(track.id);
    if (!this.selection.isSelected(track.id)) {
      this.selectedItems =
        this.selectedItems.filter((item: TrackListItem): boolean => item.id !== track.id);
    } else {
      this.selectedItems =
        this.selectedItems.filter((item: TrackListItem): boolean => item.id !== track.id)
          .concat([track]);
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

  @Builder
  private Header(detail: ArtistDetailOverview) {
    Column({ space: 18 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.person_2_fill'))
          .fontSize(58)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(132)
      .height(132)
      .borderRadius(66)
      .backgroundColor($r('app.color.glass_surface_subtle'))

      Column({ space: 7 }) {
        Text(detail.artist.name)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .maxLines(3)
        Text(`${detail.albumCount} 张专辑 · ${detail.trackCount} 首歌曲 · ` +
          this.durationLabel(detail.totalDurationMs))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }

      Row({ space: 12 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.shuffle'))
            .fontSize(20)
            .fontColor([$r('app.color.text_primary')])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor($r('app.color.glass_surface_subtle'))
        .enabled(detail.trackCount > 0 && !this.snapshotActionBusy)
        .accessibilityText('随机播放此艺术家的歌曲')
        .onClick(() => this.runSnapshotAction(
          (tracks: Array<TrackListItem>): void => playbackRuntime.shuffleAll(tracks)
        ))

        Button() {
          Row({ space: 7 }) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(19)
              .fontColor([$r('app.color.text_primary')])
            Text('播放')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
        }
        .width(180)
        .height(44)
        .borderRadius(22)
        .backgroundColor($r('app.color.glass_surface_strong'))
        .enabled(detail.trackCount > 0 && !this.snapshotActionBusy)
        .onClick(() => this.runSnapshotAction((tracks: Array<TrackListItem>): void =>
          playbackRuntime.playInOrder(tracks[0], tracks)))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: PageLayoutSpec.HORIZONTAL_INSET,
      right: PageLayoutSpec.HORIZONTAL_INSET,
      bottom: 18
    })
  }

  @Builder
  private SectionTitle(title: string, count: number) {
    Row() {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Text(`${count}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({
      left: PageLayoutSpec.HORIZONTAL_INSET,
      right: PageLayoutSpec.HORIZONTAL_INSET,
      top: 12,
      bottom: 8
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
    List({ space: 2, scroller: this.scroller }) {
      if (this.state.detail !== undefined) {
        ListItem() {
          this.Header(this.state.detail)
        }
        if (this.state.detail.albums.length > 0) {
          ListItem() {
            this.SectionTitle('专辑', this.state.detail.albumCount)
          }
          ListItem() {
            AlbumGridSection({
              store: this.store,
              albums: this.state.detail.albums,
              containerWidth: this.rootWidth,
              onOpenAlbum: this.onOpenAlbum
            })
          }
        }
        if (this.state.detail.trackCount > 0) {
          ListItem() {
            this.SectionTitle('歌曲', this.state.detail.trackCount)
          }
          LazyForEach(this.state.trackDataSource, (slot: LibrarySlot<TrackListItem>) => {
            if (slot.value !== undefined) {
              ListItem() {
                LibraryTrackRow({
                  track: slot.value,
                  store: this.store,
                  currentIdentity: this.currentIdentity,
                  variant: LibraryTrackRowVariant.LIBRARY,
                  artworkPath: slot.value.smallArtworkPath.length > 0 ?
                    this.store.resolveArtworkPath(slot.value.smallArtworkPath) : '',
                  actionAnchorPrefix: this.actionAnchorPrefix,
                  horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
                  verticalInset: 6,
                  artworkSize: 48,
                  artworkCornerRadius: 9,
                  onActivate: (item: TrackListItem): void => this.playTrack(item),
                  onOpenActions: this.onOpenTrackActions,
                  onOpenDetails: this.onOpenTrackDetails,
                  onNavigateAction: this.onNavigateTrackAction,
                  onRequestAddToPlaylist: this.onRequestAddToPlaylist,
                  selectionMode: this.selection.active,
                  selected: this.selection.isSelected(slot.value.id),
                  onToggleSelection: (item: TrackListItem): void => this.toggleSelection(item)
                })
                  .reuseId('artist_detail_track')
              }
            } else {
              ListItem() {
                LibraryTrackRowPlaceholder({
                  horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
                  verticalInset: 6,
                  minimumHeight: 60,
                  artworkSize: 48,
                  artworkCornerRadius: 9,
                  selectionMode: this.selection.active
                })
              }
            }
          }, (slot: LibrarySlot<TrackListItem>) => slot.key)
        }
      } else if (this.state.loading) {
        ListItem() {
          LoadingProgress()
            .width(40)
            .height(40)
            .margin({ top: 72 })
        }
      } else {
        ListItem() {
          Text(this.state.error.length > 0 ? this.state.error : '正在载入艺术家…')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 72 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
    .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
    .attributeModifier(this.scrollBehavior)
    .onScrollIndex((firstIndex: number, lastIndex: number, _centerIndex: number): void => {
      const detail = this.state.detail;
      if (detail === undefined || detail.trackCount === 0) {
        return;
      }
      const range: DetailTrackVisibleRange | undefined =
        DetailTrackListPagingPolicy.visibleDataRange(
          firstIndex,
          lastIndex,
          DetailTrackListPagingPolicy.artistTrackDataStartIndex(detail.albums.length > 0),
          detail.trackCount
        );
      if (range !== undefined) {
        this.state.ensureTrackRange(range.firstIndex, range.lastIndex)
          .catch((error: Object): void =>
            console.warn(`Unable to prefetch artist tracks: ${error}`));
      }
    })
    }
    .width('100%')
    .height('100%')
  }
}
