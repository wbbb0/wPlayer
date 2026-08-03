import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { AlbumPreviewGrid } from '../../components/library/AlbumPreviewGrid';
import { AlbumAction } from '../../components/library/AlbumGridItem';
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
import { LibraryStore } from '../../library/store/LibraryStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { MultiSelectController } from '../../components/library/MultiSelectController';

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
  @State snapshotActionBusy: boolean = false;
  scroller: Scroller = new Scroller();
  onOpenAlbum: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onOpenAllTracks: () => void = (): void => {};
  onOpenAllAlbums: () => void = (): void => {};
  onAlbumAction: (album: AlbumListItem, action: AlbumAction) => void =
    (_album: AlbumListItem, _action: AlbumAction): void => {};
  onOpenTrackActions: (track: TrackListItem, anchorId: string) => void =
    (_track: TrackListItem, _anchorId: string): void => {};
  onNavigateTrackAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();

  aboutToAppear(): void {
    this.state.activate(this.store);
    this.selection.cancel();
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
  private SectionTitle(title: string, count: number, showAll: boolean, onShowAll: () => void) {
    Row() {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Blank()
      if (showAll) {
        Button('查看全部')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor(Color.Transparent)
          .onClick(onShowAll)
      } else {
        Text(`${count}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
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
            this.SectionTitle(
              '专辑',
              this.state.detail.albumCount,
              this.state.detail.albumCount > this.state.detail.albums.length,
              this.onOpenAllAlbums
            )
          }
          ListItem() {
            AlbumPreviewGrid({
              store: this.store,
              albums: this.state.detail.albums,
              containerWidth: this.rootWidth,
              onOpenAlbum: this.onOpenAlbum,
              onAlbumAction: this.onAlbumAction,
              onNavigate: this.onNavigateTrackAction
            })
          }
        }
        if (this.state.detail.trackCount > 0) {
          ListItem() {
            this.SectionTitle(
              '歌曲',
              this.state.detail.trackCount,
              this.state.detail.trackCount > this.state.detail.trackPreview.length,
              this.onOpenAllTracks
            )
          }
          ForEach(this.state.detail.trackPreview, (track: TrackListItem) => {
              ListItem() {
                LibraryTrackRow({
                  track: track,
                  store: this.store,
                  currentIdentity: this.currentIdentity,
                  variant: LibraryTrackRowVariant.LIBRARY,
                  artworkPath: track.smallArtworkPath.length > 0 ?
                    this.store.resolveArtworkPath(track.smallArtworkPath) : '',
                  actionAnchorPrefix: this.actionAnchorPrefix,
                  horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
                  verticalInset: 6,
                  artworkSize: 48,
                  artworkCornerRadius: 9,
                  onActivate: (item: TrackListItem): void => this.playTrack(item),
                  onOpenActions: this.onOpenTrackActions,
                  onOpenDetails: this.onOpenTrackDetails,
                  onShareTrackFile: this.onShareTrackFile,
                  onNavigateAction: this.onNavigateTrackAction,
                  onRequestAddToPlaylist: this.onRequestAddToPlaylist
                })
                  .reuseId('artist_detail_track')
              }
          }, (track: TrackListItem) => `${track.id}`)
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
    }
    .width('100%')
    .height('100%')
  }
}
