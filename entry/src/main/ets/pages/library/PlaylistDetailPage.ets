import { HdsListItem } from '@kit.UIDesignKit';
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
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlaybackOriginKind } from '../../playback/model/PlaybackModels';
import { SongListItem, SongListItemLayout } from '../../components/library/SongListItem';
import { TrackActionMenuPresenter } from '../../components/library/TrackActionMenu';
import { promptAction } from '@kit.ArkUI';

const REMOVE_ANIMATION_DURATION: number = 180;

@Component
export struct PlaylistDetailPage {
  @ObjectLink store: PlaylistStore;
  @ObjectLink libraryStore: LibraryStore;
  @Prop playlistId: number = -1;
  @Prop rootWidth: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State removingTrackIds: Array<number> = [];
  scroller: Scroller = new Scroller();
  onResolveArtwork: (relativePath: string) => string = (_relativePath: string): string => '';
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();

  aboutToAppear(): void {
    this.store.loadDetail(this.playlistId);
  }

  private playlist(): PlaylistSummary | undefined {
    return this.store.detail?.playlist.id === this.playlistId ? this.store.detail.playlist : undefined;
  }

  private origin(): PlaybackOriginKind {
    return this.playlist()?.kind === PlaylistKind.COMPLETED_HISTORY ?
      PlaybackOriginKind.COMPLETED_PLAYLIST : PlaybackOriginKind.PLAYLIST;
  }

  private play(item: PlaylistTrackItem): void {
    const detail = this.store.detail;
    if (detail === undefined || detail.playlist.id !== this.playlistId) {
      return;
    }
    playbackRuntime.playInOrder(item, detail.items, this.origin());
    this.store.markPlayed(this.playlistId);
  }

  private durationLabel(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    return `${Math.floor(totalSeconds / 60)}:${`${totalSeconds % 60}`.padStart(2, '0')}`;
  }

  private detailItems(): Array<PlaylistTrackItem> {
    const detail = this.store.detail;
    return detail !== undefined && detail.playlist.id === this.playlistId ? detail.items : [];
  }

  private markPlayed(): void {
    this.store.markPlayed(this.playlistId);
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
      .enabled(this.detailItems().length > 0)
      .accessibilityText('随机播放此播放列表')
      .onClick(() => {
        playbackRuntime.shuffleAll(this.detailItems(), this.origin());
        this.markPlayed();
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
      .enabled(this.detailItems().length > 0)
      .onClick(() => {
        const first = this.detailItems()[0];
        if (first !== undefined) {
          this.play(first);
        }
      })

      Button() {
        this.HeaderActionIcon($r('sys.symbol.plus'))
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor($r('app.color.glass_surface_strong'))
      .enabled(this.detailItems().length > 0)
      .accessibilityText('添加到队列')
      .onClick(() => playbackRuntime.appendToQueue(this.detailItems()))
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
      [item],
      undefined,
      this.onNavigateLibrary,
      this.onRequestAddToPlaylist,
      '从此播放列表移除',
      (): void => this.confirmRemoveTrack(item)
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
    SongListItem({
      item: item,
      libraryStore: this.libraryStore,
      layout: SongListItemLayout.LIBRARY,
      artworkPath: this.onResolveArtwork(item.artworkPath),
      actionTrack: item,
      actionAnchorPrefix: `playlist_${this.playlistId}`,
      horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
      verticalInset: 7,
      artworkSize: 48,
      artworkCornerRadius: 9,
      removeActionLabel: '从此播放列表移除',
      onActivate: (): void => this.play(item),
      onOpenActions: (_track: TrackListItem, anchorId: string): void =>
        this.openTrackActions(item, anchorId),
      onNavigateAction: this.onNavigateLibrary,
      onRequestAddToPlaylist: this.onRequestAddToPlaylist,
      onRemoveAction: (): void => this.confirmRemoveTrack(item)
    })
  }

  @Builder
  private Header(playlist: PlaylistSummary) {
    Column({ space: 14 }) {
      Text(`${playlist.trackCount} 首 · ${this.durationLabel(playlist.totalDurationMs)}`)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      this.PlaybackActions()
    }
    .width('100%')
    .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET, bottom: 12 })
  }

  build() {
    List({ space: 0, scroller: this.scroller }) {
      if (this.playlist() !== undefined) {
        ListItem() {
          this.Header(this.playlist()!)
        }
      }
      if (this.store.detail?.playlist.id === this.playlistId) {
        ForEach(this.store.detail.items, (item: PlaylistTrackItem) => {
          HdsListItem({
            customItemBuilder: () => {
              this.TrackContent(item)
            },
            swipeActionOptions: {
              deleteIconOptions: {
                onAction: () => this.confirmRemoveTrack(item)
              }
            }
          })
            .height(this.isRemovingTrack(item.id) ? 0 : 62)
            .clip(true)
            .opacity(this.isRemovingTrack(item.id) ? 0 : 1)
            .translate({ x: this.isRemovingTrack(item.id) ? -28 : 0 })
        }, (item: PlaylistTrackItem) => `${item.id}`)
      }
      if (this.store.detailLoading) {
        ListItem() {
          LoadingProgress().width(36).height(36).margin({ top: 18, bottom: 18 })
        }
      }
      if (this.store.errorMessage.length > 0 || this.store.lastMessage.length > 0) {
        ListItem() {
          Text(this.store.errorMessage.length > 0 ? this.store.errorMessage : this.store.lastMessage)
            .fontSize(13)
            .fontColor(this.store.errorMessage.length > 0 ?
              $r('sys.color.ohos_id_color_warning') : $r('app.color.text_secondary'))
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
    .onReachEnd(() => this.store.loadMore())
    .attributeModifier(this.scrollBehavior)
  }
}
