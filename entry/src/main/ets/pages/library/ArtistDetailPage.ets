import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { AlbumGridSection } from '../../components/library/AlbumGridItem';
import { SongListItem, SongListItemLayout } from '../../components/library/SongListItem';
import {
  AlbumListItem,
  ArtistDetail,
  LibraryEntityIdentity,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { ArtistDetailState } from '../../library/store/LibraryDetailState';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
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
  @State selectedItems: Array<TrackListItem> = [];
  scroller: Scroller = new Scroller();
  onOpenAlbum: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onOpenTrackActions: (track: TrackListItem, anchorId: string) => void =
    (_track: TrackListItem, _anchorId: string): void => {};
  onNavigateTrackAction: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  private readonly scrollBehavior: PageListBehavior =
    new PageListBehavior(LibraryPagingPolicy.TRACK_PAGE_SIZE);

  aboutToAppear(): void {
    this.state.load(this.store);
    this.selection.deleteEnabled = false;
    this.selection.onPlay = (): void => this.playSelection();
    this.selection.onAddToPlaylist = (): void =>
      this.onRequestAddToPlaylist(this.currentSelection());
    this.selection.onInsertNext = (): void => playbackRuntime.insertNext(this.currentSelection());
    this.selection.onAppendToQueue = (): void =>
      playbackRuntime.appendToQueue(this.currentSelection());
  }

  private durationLabel(durationMs: number): string {
    const totalMinutes = Math.max(0, Math.floor(durationMs / 60000));
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;
    return hours > 0 ? `${hours} 小时 ${minutes} 分钟` : `${minutes} 分钟`;
  }

  private playFirst(detail: ArtistDetail): void {
    if (detail.tracks.length > 0) {
      playbackRuntime.playInOrder(detail.tracks[0], detail.tracks);
    }
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
  private Header(detail: ArtistDetail) {
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
        .enabled(detail.tracks.length > 0)
        .accessibilityText('随机播放此艺术家的歌曲')
        .onClick(() => playbackRuntime.shuffleAll(detail.tracks))

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
        .enabled(detail.tracks.length > 0)
        .onClick(() => this.playFirst(detail))
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
        if (this.state.detail.tracks.length > 0) {
          ListItem() {
            this.SectionTitle('歌曲', this.state.detail.trackCount)
          }
          LazyForEach(this.state.trackDataSource, (track: TrackListItem) => {
            ListItem() {
              SongListItem({
                item: track,
                libraryStore: this.store,
                currentIdentity: this.currentIdentity,
                layout: SongListItemLayout.LIBRARY,
                artworkPath: track.smallArtworkPath.length > 0 ?
                  this.store.resolveArtworkPath(track.smallArtworkPath) : '',
                actionTrack: track,
                actionAnchorPrefix: this.actionAnchorPrefix,
                horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
                verticalInset: 6,
                artworkSize: 48,
                artworkCornerRadius: 9,
                onActivate: (): void => {
                  if (this.state.detail !== undefined) {
                    playbackRuntime.playInOrder(track, this.state.detail.tracks);
                  }
                },
                onOpenActions: this.onOpenTrackActions,
                onNavigateAction: this.onNavigateTrackAction,
                onRequestAddToPlaylist: this.onRequestAddToPlaylist,
                selectionMode: this.selection.active,
                selected: this.selection.isSelected(track.id),
                onToggleSelection: (): void => this.toggleSelection(track)
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
