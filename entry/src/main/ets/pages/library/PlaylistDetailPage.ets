import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import {
  PlaylistKind,
  LibraryNavigationTarget,
  PlaylistSummary,
  PlaylistTrackItem,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlaybackOriginKind } from '../../playback/model/PlaybackModels';
import {
  LibraryTrackRow,
  LibraryTrackRowVariant
} from '../../components/library/LibraryTrackRow';
import { LibraryEmptyState } from '../../components/library/LibraryEmptyState';
import { TrackActionMenuPresenter } from '../../components/library/TrackActionMenu';
import { promptAction } from '@kit.ArkUI';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import { LibrarySlot } from '../../library/store/PagedLibraryDataSource';
import { LibraryTrackRowPlaceholder } from '../../components/library/LibraryTrackRowPlaceholder';
import {
  DetailTrackListPagingPolicy,
  DetailTrackVisibleRange
} from '../../library/store/DetailTrackListPagingPolicy';

const REMOVE_ANIMATION_DURATION: number = 180;

@Component
export struct PlaylistDetailPage {
  @ObjectLink store: PlaylistStore;
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink selection: MultiSelectController;
  @Prop playlistId: number = -1;
  @Prop rootWidth: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State removingTrackIds: Array<number> = [];
  @State selectedItems: Array<PlaylistTrackItem> = [];
  @State snapshotActionBusy: boolean = false;
  scroller: Scroller = new Scroller();
  onResolveArtwork: (relativePath: string) => string = (_relativePath: string): string => '';
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  private readonly scrollBehavior: PageListBehavior =
    new PageListBehavior(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT);

  aboutToAppear(): void {
    this.store.loadDetail(this.playlistId);
    this.selection.deleteEnabled = true;
    this.selection.onPlay = (): void => this.playSelection();
    this.selection.onAddToPlaylist = (): void =>
      this.onRequestAddToPlaylist(this.currentSelection());
    this.selection.onInsertNext = (): void => playbackRuntime.insertNext(this.currentSelection());
    this.selection.onAppendToQueue = (): void =>
      playbackRuntime.appendToQueue(this.currentSelection());
    this.selection.onDelete = (): void => this.confirmRemoveSelection();
    this.selection.onToggleAll = (): void => this.toggleAll();
  }

  private toggleAll(): void {
    if (this.selection.allSelected()) {
      this.selectedItems = [];
      this.selection.replaceSelection([]);
      return;
    }
    const playlistId = this.playlistId;
    this.selection.setBusy(true);
    this.store.getAllTracks(playlistId).then((items: Array<PlaylistTrackItem>): void => {
      if (this.playlistId !== playlistId) {
        return;
      }
      this.selectedItems = items;
      this.selection.selectableCount = items.length;
      this.selection.replaceSelection(items.map((item: PlaylistTrackItem): number => item.id));
    }).catch((error: Object): void => {
      console.warn(`Unable to select all playlist tracks: ${error}`);
    }).finally((): void => this.selection.setBusy(false));
  }

  private playlist(): PlaylistSummary | undefined {
    return this.store.detailOverview?.playlist.id === this.playlistId ?
      this.store.detailOverview.playlist : undefined;
  }

  private origin(): PlaybackOriginKind {
    return this.playlist()?.kind === PlaylistKind.COMPLETED_HISTORY ?
      PlaybackOriginKind.COMPLETED_PLAYLIST : PlaybackOriginKind.PLAYLIST;
  }

  private play(item: PlaylistTrackItem): void {
    this.runSnapshotAction((items: Array<PlaylistTrackItem>): void => {
      const current = items.find((candidate: PlaylistTrackItem): boolean => candidate.id === item.id);
      if (current !== undefined) {
        playbackRuntime.playInOrder(current, items, this.origin());
        this.store.markPlayed(this.playlistId);
      }
    });
  }

  private durationLabel(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    return `${Math.floor(totalSeconds / 60)}:${`${totalSeconds % 60}`.padStart(2, '0')}`;
  }

  private detailTrackCount(): number {
    const detail = this.store.detailOverview;
    return detail !== undefined && detail.playlist.id === this.playlistId ? detail.totalCount : 0;
  }

  private runSnapshotAction(action: (items: Array<PlaylistTrackItem>) => void): void {
    if (this.snapshotActionBusy) {
      return;
    }
    const playlistId = this.playlistId;
    this.snapshotActionBusy = true;
    this.store.getAllTracks(playlistId).then((items: Array<PlaylistTrackItem>): void => {
      if (this.playlistId === playlistId &&
        this.store.detailOverview?.playlist.id === playlistId && items.length > 0) {
        action(items);
      }
      this.snapshotActionBusy = false;
    }).catch((error: Object): void => {
      console.warn(`Unable to load playlist playback order: ${error}`);
      this.snapshotActionBusy = false;
    });
  }

  private detailEmpty(): boolean {
    const detail = this.store.detailOverview;
    return detail !== undefined && detail.playlist.id === this.playlistId && detail.totalCount === 0 &&
      !this.store.detailLoading && this.store.errorMessage.length === 0;
  }

  private emptyTitle(): string {
    return this.playlist()?.kind === PlaylistKind.COMPLETED_HISTORY ? '还没有播放记录' : '播放列表是空的';
  }

  private emptyDescription(): string {
    return this.playlist()?.kind === PlaylistKind.COMPLETED_HISTORY ?
      '完整播放过的歌曲会自动出现在这里' :
      '从歌曲或专辑的更多操作中添加音乐，之后就能按这个列表播放';
  }

  private markPlayed(): void {
    this.store.markPlayed(this.playlistId);
  }

  private currentSelection(): Array<PlaylistTrackItem> {
    return this.selectedItems.filter((item: PlaylistTrackItem): boolean =>
      this.selection.isSelected(item.id));
  }

  private toggleSelection(item: PlaylistTrackItem): void {
    this.selection.toggle(item.id);
    if (!this.selection.isSelected(item.id)) {
      this.selectedItems =
        this.selectedItems.filter((selected: PlaylistTrackItem): boolean => selected.id !== item.id);
    } else {
      this.selectedItems =
        this.selectedItems.filter((selected: PlaylistTrackItem): boolean => selected.id !== item.id)
          .concat([item]);
    }
  }

  private playSelection(): void {
    const items = this.currentSelection();
    if (items.length > 0) {
      playbackRuntime.playInOrder(items[0], items, this.origin());
      this.markPlayed();
      this.selectedItems = [];
      this.selection.cancel();
    }
  }

  private confirmRemoveSelection(): void {
    const items = this.currentSelection();
    if (items.length === 0 || this.store.mutating) {
      return;
    }
    const count = items.length;
    this.getUIContext().getPromptAction().showDialog({
      title: '从播放列表移除',
      message: `确定移除选中的 ${count} 首歌曲吗？音乐文件不会被删除。`,
      buttons: [
        { text: '取消', color: $r('app.color.text_primary') },
        { text: '移除', color: $r('sys.color.ohos_id_color_warning') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index !== 1) {
        return;
      }
      const ids = items.map((item: PlaylistTrackItem): number => item.id);
      this.store.removeTracks(this.playlistId, ids).then((removed: boolean): void => {
        if (removed) {
          this.selectedItems = [];
          this.selection.cancel();
        }
      });
    }).catch((_error: Object): void => {});
  }

  @Builder
  private HeaderActionIcon(symbol: Resource) {
    SymbolGlyph(symbol)
      .fontSize(20)
      .fontColor([$r('app.color.theme_accent')])
  }

  @Builder
  private PlaybackActions() {
    Row({ space: 12 }) {
      Button() {
        this.HeaderActionIcon($r('sys.symbol.shuffle'))
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.glass_surface_strong'))
      .enabled(this.detailTrackCount() > 0 && !this.snapshotActionBusy)
      .accessibilityText('随机播放此播放列表')
      .onClick(() => {
        this.runSnapshotAction((items: Array<PlaylistTrackItem>): void => {
          playbackRuntime.shuffleAll(items, this.origin());
          this.markPlayed();
        });
      })

      Button() {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(19)
            .fontColor([$r('app.color.control_on_accent')])
          Text('播放')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.control_on_accent'))
        }
      }
      .width(Math.min(
        PageLayoutSpec.DETAIL_PRIMARY_PLAY_MAX_WIDTH,
        Math.max(PageLayoutSpec.DETAIL_PRIMARY_PLAY_MIN_WIDTH, this.rootWidth - 164)
      ))
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.theme_accent'))
      .enabled(this.detailTrackCount() > 0 && !this.snapshotActionBusy)
      .onClick(() => {
        this.runSnapshotAction((items: Array<PlaylistTrackItem>): void => {
          playbackRuntime.playInOrder(items[0], items, this.origin());
          this.markPlayed();
        });
      })

      Button() {
        this.HeaderActionIcon($r('sys.symbol.plus'))
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.glass_surface_strong'))
      .enabled(this.detailTrackCount() > 0 && !this.snapshotActionBusy)
      .accessibilityText('添加到队列')
      .onClick(() => this.runSnapshotAction(
        (items: Array<PlaylistTrackItem>): void => playbackRuntime.appendToQueue(items)
      ))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  private openTrackActions(item: PlaylistTrackItem, anchorId: string): void {
    TrackActionMenuPresenter.open(
      this.getUIContext(),
      this.libraryStore,
      item.id,
      anchorId,
      {
        queueItems: [item],
        onNavigate: this.onNavigateLibrary,
        onRequestAddToPlaylist: this.onRequestAddToPlaylist,
        onShareTrackFile: this.onShareTrackFile,
        removeLabel: '从此播放列表移除',
        onRemove: (): void => this.confirmRemoveTrack(item),
        onOpenDetails: this.onOpenTrackDetails
      }
    );
  }

  private isRemovingTrack(trackId: number): boolean {
    return this.removingTrackIds.includes(trackId);
  }

  private confirmRemoveTrack(item: PlaylistTrackItem): void {
    if (this.store.mutating || this.isRemovingTrack(item.id)) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '从播放列表移除',
      message: `确定移除“${item.title}”吗？音乐文件不会被删除。`,
      buttons: [
        { text: '取消', color: $r('app.color.text_primary') },
        { text: '移除', color: $r('sys.color.ohos_id_color_warning') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) {
        this.animateTrackRemoval(item.id);
      }
    }).catch((_error: Object): void => {
      // Closing the dialog is equivalent to cancelling the destructive action.
    });
  }

  private animateTrackRemoval(trackId: number): void {
    if (this.isRemovingTrack(trackId)) {
      return;
    }
    this.getUIContext().animateTo({
      duration: REMOVE_ANIMATION_DURATION,
      curve: Curve.EaseIn,
      onFinish: (): void => {
        this.store.removeTrack(this.playlistId, trackId).then((removed: boolean): void => {
          if (removed) {
            this.removingTrackIds = this.removingTrackIds.filter((id: number): boolean => id !== trackId);
            return;
          }
          this.getUIContext().animateTo({
            duration: REMOVE_ANIMATION_DURATION,
            curve: Curve.EaseOut
          }, (): void => {
            this.removingTrackIds = this.removingTrackIds.filter((id: number): boolean => id !== trackId);
          });
        });
      }
    }, (): void => {
      this.removingTrackIds = this.removingTrackIds.concat([trackId]);
    });
  }

  @Builder
  private TrackContent(item: PlaylistTrackItem) {
    LibraryTrackRow({
      track: item,
      store: this.libraryStore,
      variant: LibraryTrackRowVariant.LIBRARY,
      artworkPath: this.onResolveArtwork(item.artworkPath),
      actionAnchorPrefix: `playlist_${this.playlistId}`,
      horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
      verticalInset: 7,
      artworkSize: 48,
      artworkCornerRadius: 9,
      removeActionLabel: '从此播放列表移除',
      onActivate: (track: TrackListItem): void => this.play(track as PlaylistTrackItem),
      onOpenActions: (track: TrackListItem, anchorId: string): void =>
        this.openTrackActions(track as PlaylistTrackItem, anchorId),
      onOpenDetails: this.onOpenTrackDetails,
      onShareTrackFile: this.onShareTrackFile,
      onNavigateAction: this.onNavigateLibrary,
      onRequestAddToPlaylist: this.onRequestAddToPlaylist,
      onRemoveAction: (): void => this.confirmRemoveTrack(item),
      selectionMode: this.selection.active,
      selected: this.selection.isSelected(item.id),
      onToggleSelection: (track: TrackListItem): void =>
        this.toggleSelection(track as PlaylistTrackItem)
    })
  }

  @Builder
  private TrackPlaceholder() {
    LibraryTrackRowPlaceholder({
      horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
      verticalInset: 7,
      minimumHeight: 62,
      artworkSize: 48,
      artworkCornerRadius: 9,
      selectionMode: this.selection.active
    })
  }

  @Builder
  private Header() {
    Column({ space: 14 }) {
      if (this.store.detailOverview?.playlist.id === this.playlistId) {
        Text(this.durationLabel(this.store.detailOverview.playlist.totalDurationMs))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        if (this.store.detailOverview.playlist.trackCount > 0) {
          this.PlaybackActions()
        }
      }
    }
    .width('100%')
    .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET, bottom: 12 })
  }

  build() {
    if (this.detailEmpty()) {
      LibraryEmptyState({
        symbol: $r('sys.symbol.music_fill'),
        title: this.emptyTitle(),
        description: this.emptyDescription(),
        loading: false,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller
      })
    } else {
      Stack({ alignContent: Alignment.Bottom }) {
        List({ space: 0, scroller: this.scroller }) {
          if (this.playlist() !== undefined) {
            ListItem() {
              this.Header()
            }
          }
          if (this.store.detailOverview?.playlist.id === this.playlistId) {
            LazyForEach(this.store.detailItemDataSource, (slot: LibrarySlot<PlaylistTrackItem>) => {
              if (slot.value !== undefined) {
                ListItem() {
                  this.TrackContent(slot.value!)
                }
                  .height(this.isRemovingTrack(slot.value.id) ? 0 : 62)
                  .clip(true)
                  .opacity(this.isRemovingTrack(slot.value.id) ? 0 : 1)
                  .translate({ x: this.isRemovingTrack(slot.value.id) ? -28 : 0 })
              } else {
                ListItem() {
                  this.TrackPlaceholder()
                }
                  .height(62)
              }
            }, (slot: LibrarySlot<PlaylistTrackItem>) => slot.key)
          }
          if (this.store.detailLoading) {
            ListItem() {
              LoadingProgress().width(36).height(36).margin({ top: 18, bottom: 18 })
            }
          }
          if (this.store.errorMessage.length > 0) {
            ListItem() {
              Text(this.store.errorMessage)
                .fontSize(13)
                .fontColor($r('sys.color.ohos_id_color_warning'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 12, bottom: 12 })
            }
          }
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
        .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
        .attributeModifier(this.scrollBehavior)
        .onScrollIndex((firstIndex: number, lastIndex: number, _centerIndex: number): void => {
          const range: DetailTrackVisibleRange | undefined =
            DetailTrackListPagingPolicy.visibleDataRange(
              firstIndex,
              lastIndex,
              DetailTrackListPagingPolicy.playlistTrackDataStartIndex(),
              this.detailTrackCount()
            );
          if (range !== undefined) {
            this.store.ensureDetailRange(range.firstIndex, range.lastIndex)
              .catch((error: Object): void =>
                console.warn(`Unable to prefetch playlist tracks: ${error}`));
          }
        })
      }
      .width('100%')
      .height('100%')
    }
  }
}
