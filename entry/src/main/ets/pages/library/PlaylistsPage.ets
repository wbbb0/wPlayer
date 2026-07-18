import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import {
  PlaylistKind,
  PlaylistSummary
} from '../../library/model/LibraryModels';
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { promptAction } from '@kit.ArkUI';
import { HdsListItem } from '@kit.UIDesignKit';

const DELETE_ANIMATION_DURATION: number = 180;

@Component
export struct PlaylistsPage {
  @ObjectLink store: PlaylistStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  onOpenPlaylist: (playlist: PlaylistSummary) => void = (_playlist: PlaylistSummary): void => {};
  onRequestRename: (playlist: PlaylistSummary) => void = (_playlist: PlaylistSummary): void => {};
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();
  @State private removingPlaylistIds: Array<number> = [];

  private durationLabel(durationMs: number): string {
    const totalMinutes = Math.floor(Math.max(0, durationMs) / 60000);
    if (totalMinutes < 60) {
      return `${totalMinutes} 分钟`;
    }
    return `${Math.floor(totalMinutes / 60)} 小时 ${totalMinutes % 60} 分钟`;
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
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph(playlist.kind === PlaylistKind.COMPLETED_HISTORY ?
          $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.music_note_list_fill'))
          .fontSize(28)
          .fontColor([$r('app.color.theme_accent')])
      }
      .width(54)
      .height(54)
      .borderRadius(14)
      .backgroundColor($r('app.color.glass_surface_strong'))

      Column({ space: 4 }) {
        Row({ space: 7 }) {
          Text(playlist.name)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
          if (playlist.kind === PlaylistKind.COMPLETED_HISTORY) {
            Text('自动')
              .fontSize(10)
              .fontColor($r('app.color.theme_accent'))
          }
        }
        Text(`${playlist.trackCount} 首 · ${this.durationLabel(playlist.totalDurationMs)}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button() {
        Image($r('app.media.control_more'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.text_primary'))
      }
      .width(38)
      .height(38)
      .borderRadius(19)
      .backgroundColor(Color.Transparent)
      .accessibilityText('更多播放列表操作')
      .bindMenu(this.PlaylistMenu(playlist), { placement: Placement.BottomRight })
    }
    .width('100%')
    .padding(14)
    .borderRadius(20)
    .backgroundColor($r('app.color.glass_surface'))
    .onClick(() => this.onOpenPlaylist(playlist))
    .bindContextMenu(
      this.PlaylistMenu(playlist),
      ResponseType.LongPress,
      { preview: MenuPreviewMode.IMAGE }
    )
  }

  build() {
    List({ space: 10, scroller: this.scroller }) {
      ForEach(this.store.playlists, (playlist: PlaylistSummary) => {
        if (playlist.kind === PlaylistKind.USER) {
          HdsListItem({
            customItemBuilder: () => {
              this.PlaylistContent(playlist)
            },
            swipeActionOptions: {
              deleteIconOptions: {
                onAction: () => this.confirmDelete(playlist)
              }
            }
          })
            .height(this.isRemovingPlaylist(playlist.id) ? 0 : 82)
            .clip(true)
            .opacity(this.isRemovingPlaylist(playlist.id) ? 0 : 1)
            .translate({ x: this.isRemovingPlaylist(playlist.id) ? -28 : 0 })
        } else {
          HdsListItem({
            customItemBuilder: () => {
              this.PlaylistContent(playlist)
            }
          })
        }
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
      if (this.store.lastMessage.length > 0) {
        ListItem() {
          Text(this.store.lastMessage)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET })
    .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
    .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
    .attributeModifier(this.scrollBehavior)
  }
}
