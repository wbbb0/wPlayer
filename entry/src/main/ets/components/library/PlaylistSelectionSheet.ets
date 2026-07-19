import { PlaylistKind, PlaylistSummary } from '../../library/model/LibraryModels';
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { LibraryListDataSource } from '../../library/store/LibraryListDataSource';
import { PageLayoutSpec } from '../layout/PageLayoutSpec';

@Component
export struct PlaylistSelectionSheet {
  @ObjectLink store: PlaylistStore;
  @Prop trackIds: Array<number> = [];
  @Prop recentPlaylistIds: Array<number> = [];
  onClose: () => void = (): void => {};
  onAddedToPlaylist: (playlistId: number) => void = (_playlistId: number): void => {};
  private readonly recentDataSource: LibraryListDataSource<PlaylistSummary> =
    new LibraryListDataSource<PlaylistSummary>();
  private readonly otherDataSource: LibraryListDataSource<PlaylistSummary> =
    new LibraryListDataSource<PlaylistSummary>();

  aboutToAppear(): void {
    this.recentDataSource.replace(this.recentPlaylists());
    this.otherDataSource.replace(this.otherPlaylists());
  }

  private addTo(playlist: PlaylistSummary): void {
    if (this.trackIds.length === 0 || this.store.mutating) {
      return;
    }
    this.store.addTrackIds(playlist.id, this.trackIds).then((result) => {
      if (result !== undefined) {
        this.onAddedToPlaylist(playlist.id);
        this.onClose();
      }
    });
  }

  private recentPlaylists(): Array<PlaylistSummary> {
    const result: Array<PlaylistSummary> = [];
    for (let idIndex = 0; idIndex < this.recentPlaylistIds.length && result.length < 3; idIndex += 1) {
      for (let playlistIndex = 0; playlistIndex < this.store.playlists.length; playlistIndex += 1) {
        const playlist = this.store.playlists[playlistIndex];
        if (playlist.id === this.recentPlaylistIds[idIndex]) {
          result.push(playlist);
          break;
        }
      }
    }
    return result;
  }

  private otherPlaylists(): Array<PlaylistSummary> {
    const recentIds: Set<number> = new Set<number>();
    const recent = this.recentPlaylists();
    for (let index = 0; index < recent.length; index += 1) {
      recentIds.add(recent[index].id);
    }
    return this.store.playlists.filter((playlist: PlaylistSummary): boolean =>
      !recentIds.has(playlist.id));
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 4, top: 8, bottom: 2 })
  }

  @Builder
  private PlaylistRow(playlist: PlaylistSummary) {
    Row({ space: 12 }) {
      SymbolGlyph(playlist.kind === PlaylistKind.COMPLETED_HISTORY ?
        $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.music_note_list_fill'))
        .fontSize(24)
        .fontColor([$r('app.color.theme_accent')])
      Column({ space: 3 }) {
        Text(playlist.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text(`${playlist.trackCount} 首`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding(14)
    .borderRadius(18)
    .backgroundColor($r('app.color.glass_surface'))
    .onClick(() => this.addTo(playlist))
  }

  build() {
    Column({ space: 14 }) {
      Column({ space: 4 }) {
        Text('添加到播放列表')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.trackIds.length === 1 ? '选择一个播放列表' : `将 ${this.trackIds.length} 首音乐添加到`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.store.playlists.length === 0) {
        Text('还没有播放列表，请先在播放列表页面新建')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 32, bottom: 32 })
      } else {
        List({ space: 8 }) {
          if (this.recentPlaylists().length > 0) {
            ListItem() {
              this.SectionTitle('最近添加到')
            }
            LazyForEach(this.recentDataSource, (playlist: PlaylistSummary) => {
              ListItem() {
                this.PlaylistRow(playlist)
              }
            }, (playlist: PlaylistSummary) => `recent_${playlist.id}`)
          }
          if (this.otherPlaylists().length > 0) {
            ListItem() {
              this.SectionTitle(this.recentPlaylists().length > 0 ? '其他播放列表' : '全部播放列表')
            }
            LazyForEach(this.otherDataSource, (playlist: PlaylistSummary) => {
              ListItem() {
                this.PlaylistRow(playlist)
              }
            }, (playlist: PlaylistSummary) => `other_${playlist.id}`)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(PageLayoutSpec.VIRTUAL_LIST_CACHE_COUNT, true)
      }

      if (this.store.errorMessage.length > 0) {
        Text(this.store.errorMessage)
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 22, bottom: 20 })
  }
}
