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
import { SongListItem, SongListItemData, SongListItemLayout } from '../../components/library/SongListItem';

const DELETE_ANIMATION_DURATION: number = 180;

@Component
export struct PlaylistsPage {
  @ObjectLink store: PlaylistStore;
  @ObjectLink selection: MultiSelectController;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  onOpenPlaylist: (playlist: PlaylistSummary) => void = (_playlist: PlaylistSummary): void => {};
  onRequestRename: (playlist: PlaylistSummary) => void = (_playlist: PlaylistSummary): void => {};
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();
  @State private removingPlaylistIds: Array<number> = [];
  @State private selectedPlaylists: Array<PlaylistSummary> = [];
  @State private selectionBusy: boolean = false;
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
  }

  private durationLabel(durationMs: number): string {
    const totalMinutes = Math.floor(Math.max(0, durationMs) / 60000);
    if (totalMinutes < 60) {
      return `${totalMinutes} 分钟`;
    }
    return `${Math.floor(totalMinutes / 60)} 小时 ${totalMinutes % 60} 分钟`;
  }

  private playlistItem(playlist: PlaylistSummary): SongListItemData {
    return {
      id: playlist.id,
      title: playlist.name,
      artistDisplay: `${playlist.trackCount} 首 · ${this.durationLabel(playlist.totalDurationMs)}`,
      durationMs: 0,
      artworkWidth: 0,
      artworkHeight: 0
    };
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

  private showSuccessDialog(message: string): void {
    if (message.length === 0) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '操作完成',
      message: message,
      buttons: [
        { text: '确定', color: $r('app.color.text_primary') }
      ]
    }).catch((_error: Object): void => {
      // The message is informational; dismissing it needs no recovery.
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
    this.selection.toggle(playlist.id);
    if (!this.selection.isSelected(playlist.id)) {
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
            this.showSuccessDialog(this.store.lastMessage);
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
      if (playlist.kind === PlaylistKind.USER) {
        MenuItem({ content: '改名' })
          .onClick(() => this.onRequestRename(playlist))
        MenuItem({ content: '删除播放列表' })
          .onClick(() => this.confirmDelete(playlist))
      }
    }
    .width(224)
  }

  @Builder
  private PlaylistContent(playlist: PlaylistSummary) {
    SongListItem({
      item: this.playlistItem(playlist),
      layout: SongListItemLayout.LIBRARY,
      showDuration: false,
      leadingSymbol: playlist.kind === PlaylistKind.COMPLETED_HISTORY ?
        $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.music_note_list_fill'),
      horizontalInset: 16,
      verticalInset: 8,
      artworkSize: 52,
      artworkCornerRadius: 10,
      customContextMenuEnabled: true,
      customTrailingMenuEnabled: !this.selection.active,
      customTrailingMenuAccessibilityText: '更多播放列表操作',
      customContextMenu: (): void => this.PlaylistMenu(playlist),
      actionAnchorPrefix: 'playlists',
      selectionMode: this.selection.active,
      selected: this.selection.isSelected(playlist.id),
      onActivate: (): void => this.onOpenPlaylist(playlist),
      onToggleSelection: (): void => this.toggleSelection(playlist)
    })
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
            this.PlaylistContent(playlist)
          }
          .width('100%')
        }
        .height(this.isRemovingPlaylist(playlist.id) ? 0 : 68)
        .clip(true)
        .opacity(this.isRemovingPlaylist(playlist.id) ? 0 : 1)
        .translate({ x: this.isRemovingPlaylist(playlist.id) ? -28 : 0 })
      }, (playlist: PlaylistSummary) => `${playlist.id}`)

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
    .attributeModifier(this.scrollBehavior)
    }
    .width('100%')
    .height('100%')
  }
}
