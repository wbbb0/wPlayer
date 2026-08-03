import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import {
  PlaylistKind,
  PlaylistSummary,
  TrackListItem
} from '../../library/model/LibraryModels';
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { promptAction } from '@kit.ArkUI';
import { MultiSelectController } from '../../components/library/MultiSelectController';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlaylistListRow } from '../../components/library/PlaylistListRow';
import {
  MenuSectionDivider
} from '../../components/library/MenuActionGroups';
import {
  DragSelectionController,
  DragSelectionHitMode
} from '../../components/library/DragSelectionController';

const DELETE_ANIMATION_DURATION: number = 180;

@Component
export struct PlaylistsPage {
  @ObjectLink store: PlaylistStore;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly dragSelection: DragSelectionController = new DragSelectionController(
    (ids: Array<number>, selected: boolean): void => this.selection.previewSelection(ids, selected),
    (active: boolean): void => { this.selectionDragActive = active; }
  );
  onOpenPlaylist: (playlist: PlaylistSummary) => void = (_playlist: PlaylistSummary): void => {};
  onRequestRename: (playlist: PlaylistSummary) => void = (_playlist: PlaylistSummary): void => {};
  onExportPlaylist: (playlistId: number) => void = (_playlistId: number): void => {};
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();
  @State private removingPlaylistIds: Array<number> = [];
  @State private selectedPlaylists: Array<PlaylistSummary> = [];
  @State private selectionBusy: boolean = false;
  @State private selectionDragActive: boolean = false;
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};

  aboutToAppear(): void {
    this.selection.deleteEnabled = false;
    this.selection.onPlay = (): void => this.runSelection((tracks: Array<TrackListItem>): void => {
      playbackRuntime.playInOrder(tracks[0], tracks);
      this.selection.cancel();
    });
    this.selection.onAddToPlaylist = (): void => this.runSelection(this.onRequestAddToPlaylist);
    this.selection.onInsertNext = (): void => this.runSelection(
      (tracks: Array<TrackListItem>): void => playbackRuntime.insertNext(tracks)
    );
    this.selection.onAppendToQueue = (): void => this.runSelection(
      (tracks: Array<TrackListItem>): void => playbackRuntime.appendToQueue(tracks)
    );
    this.selection.selectableCount = this.store.playlists.length;
    this.selection.onToggleAll = (): void => {
      if (this.selection.allSelected()) {
        this.selectedPlaylists = [];
        this.selection.replaceSelection([]);
      } else {
        this.selectedPlaylists = this.store.playlists.slice();
        this.selection.selectableCount = this.selectedPlaylists.length;
        this.selection.replaceSelection(
          this.selectedPlaylists.map((playlist: PlaylistSummary): number => playlist.id)
        );
      }
    };
  }

  aboutToDisappear(): void {
    this.dragSelection.end();
  }

  private durationLabel(durationMs: number): string {
    const totalMinutes = Math.floor(Math.max(0, durationMs) / 60000);
    if (totalMinutes < 60) {
      return `${totalMinutes} 分钟`;
    }
    return `${Math.floor(totalMinutes / 60)} 小时 ${totalMinutes % 60} 分钟`;
  }

  private playlistSubtitle(playlist: PlaylistSummary): string {
    return `${playlist.trackCount} 首 · ${this.durationLabel(playlist.totalDurationMs)}`;
  }

  private confirmDelete(playlist: PlaylistSummary): void {
    if (playlist.kind !== PlaylistKind.USER) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '删除播放列表',
      message: `确定删除“${playlist.name}”吗？音乐文件不会被删除。`,
      buttons: [
        { text: '取消', color: $r('app.color.text_primary') },
        { text: '删除', color: $r('sys.color.ohos_id_color_warning') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.animatePlaylistRemoval(playlist.id);
      }
    }).catch((_error: Object) => {
      // Closing the dialog is equivalent to cancelling the destructive action.
    });
  }

  private isRemovingPlaylist(playlistId: number): boolean {
    return this.removingPlaylistIds.includes(playlistId);
  }

  private currentSelection(): Array<PlaylistSummary> {
    return this.selectedPlaylists.filter((playlist: PlaylistSummary): boolean =>
      this.selection.isSelected(playlist.id));
  }

  private toggleSelection(playlist: PlaylistSummary): void {
    this.setSelection(playlist, !this.selection.isSelected(playlist.id));
  }

  private setSelection(playlist: PlaylistSummary, selected: boolean): void {
    this.selection.setSelected(playlist.id, selected);
    if (!selected) {
      this.selectedPlaylists =
        this.selectedPlaylists.filter((item: PlaylistSummary): boolean => item.id !== playlist.id);
    } else {
      this.selectedPlaylists =
        this.selectedPlaylists.filter((item: PlaylistSummary): boolean => item.id !== playlist.id)
          .concat([playlist]);
    }
  }

  private async selectedTracks(): Promise<Array<TrackListItem>> {
    const tracks: Array<TrackListItem> = [];
    const playlists = this.currentSelection();
    for (let index = 0; index < playlists.length; index += 1) {
      const items = await this.store.getAllTracks(playlists[index].id);
      items.forEach((track: TrackListItem): void => {
        if (!tracks.some((existing: TrackListItem): boolean => existing.id === track.id)) {
          tracks.push(track);
        }
      });
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
        this.selectedPlaylists = [];
        this.selection.cancel();
      }
    }).finally((): void => {
      this.selectionBusy = false;
      this.selection.setBusy(false);
    });
  }

  private animatePlaylistRemoval(playlistId: number): void {
    if (this.store.mutating || this.isRemovingPlaylist(playlistId)) {
      return;
    }
    this.getUIContext().animateTo({
      duration: DELETE_ANIMATION_DURATION,
      curve: Curve.EaseIn,
      onFinish: (): void => {
        this.store.delete(playlistId).then((deleted: boolean): void => {
          if (deleted) {
            this.removingPlaylistIds =
              this.removingPlaylistIds.filter((id: number): boolean => id !== playlistId);
            return;
          }
          this.getUIContext().animateTo({
            duration: DELETE_ANIMATION_DURATION,
            curve: Curve.EaseOut
          }, (): void => {
            this.removingPlaylistIds =
              this.removingPlaylistIds.filter((id: number): boolean => id !== playlistId);
          });
        });
      }
    }, (): void => {
      this.removingPlaylistIds = this.removingPlaylistIds.concat([playlistId]);
    });
  }

  @Builder
  private PlaylistMenu(playlist: PlaylistSummary) {
    Menu() {
      MenuItem({ content: '播放' })
        .onClick(() => this.onOpenPlaylist(playlist))
      MenuSectionDivider()
      MenuItem({ content: '导出为 M3U8' })
        .onClick(() => this.onExportPlaylist(playlist.id))
      if (playlist.kind === PlaylistKind.USER) {
        MenuSectionDivider()
        MenuItem({ content: '改名' })
          .onClick(() => this.onRequestRename(playlist))
        MenuSectionDivider()
        MenuItem({ content: '删除播放列表' })
          .onClick(() => this.confirmDelete(playlist))
      }
    }
    .width(224)
  }

  @Builder
  private PlaylistContent(playlist: PlaylistSummary, order: number) {
    PlaylistListRow({
      playlist: playlist,
      subtitle: this.playlistSubtitle(playlist),
      leadingSymbol: playlist.kind === PlaylistKind.COMPLETED_HISTORY ?
        $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.music_note_list_fill'),
      horizontalInset: 16,
      verticalInset: 8,
      leadingSize: 52,
      leadingCornerRadius: 10,
      contextMenu: (): void => this.PlaylistMenu(playlist),
      actionAnchorPrefix: 'playlists',
      selectionMode: this.selection.active,
      selected: this.selection.isPresentedSelected(playlist.id),
      onActivate: this.onOpenPlaylist,
      onToggleSelection: (item: PlaylistSummary): void => this.toggleSelection(item),
      onSelectionTargetAreaChange: (item: PlaylistSummary, area: Area): void =>
        this.dragSelection.updateTarget(item.id, order, area, DragSelectionHitMode.ROW,
          (): boolean => this.selection.isSelected(item.id),
          (selected: boolean): void => this.setSelection(item, selected)),
      onSelectionTargetRemoved: (id: number): void => this.dragSelection.removeTarget(id),
      onSelectionDragStart: (item: PlaylistSummary, _x: number, _y: number): void =>
        this.dragSelection.start(item.id),
      onSelectionDragUpdate: (x: number, y: number): void => this.dragSelection.update(x, y),
      onSelectionDragEnd: (): void => this.dragSelection.end(),
      onSelectionDragCancel: (): void => this.dragSelection.cancel()
    })
      .reuseId('playlists')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
    List({ space: 0, scroller: this.scroller }) {
      LazyForEach(this.store.playlistDataSource, (playlist: PlaylistSummary, index: number) => {
        ListItem() {
          Column() {
            if (index > 0) {
              Divider()
                .color($r('app.color.text_tertiary'))
                .opacity(0.3)
                .margin({ left: 80, right: PageLayoutSpec.HORIZONTAL_INSET })
            }
            this.PlaylistContent(playlist, index)
          }
          .width('100%')
        }
        .height(this.isRemovingPlaylist(playlist.id) ? 0 : 68)
        .clip(true)
        .opacity(this.isRemovingPlaylist(playlist.id) ? 0 : 1)
        .translate({ x: this.isRemovingPlaylist(playlist.id) ? -28 : 0 })
      }, (playlist: PlaylistSummary) => this.store.playlistDataSource.keyFor(playlist.id))

      if (this.store.loading) {
        ListItem() {
          LoadingProgress().width(36).height(36).margin({ top: 24 })
        }
      }
      if (this.store.errorMessage.length > 0) {
        ListItem() {
          Text(this.store.errorMessage)
            .fontSize(13)
            .fontColor($r('sys.color.ohos_id_color_warning'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
    }
    .width('100%')
    .height('100%')
    .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
    .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
    .enableScrollInteraction(!this.selectionDragActive)
    .attributeModifier(this.scrollBehavior)
    }
    .width('100%')
    .height('100%')
  }
}
