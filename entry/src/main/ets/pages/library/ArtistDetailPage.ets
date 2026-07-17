import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { AlbumGridSection } from '../../components/library/AlbumGridItem';
import { SongListItem, SongListItemLayout } from '../../components/library/SongListItem';
import {
  AlbumListItem,
  ArtistDetail,
  TrackListItem
} from '../../library/model/LibraryModels';
import { ArtistDetailState } from '../../library/store/LibraryDetailState';
import { LibraryStore } from '../../library/store/LibraryStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';

@Component
export struct ArtistDetailPage {
  @ObjectLink store: LibraryStore;
  @ObjectLink state: ArtistDetailState;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @Prop actionAnchorPrefix: string = 'artist';
  scroller: Scroller = new Scroller();
  onOpenAlbum: (album: AlbumListItem) => void = (_album: AlbumListItem): void => {};
  onOpenTrackActions: (track: TrackListItem, anchorId: string) => void =
    (_track: TrackListItem, _anchorId: string): void => {};
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();

  aboutToAppear(): void {
    this.state.load(this.store);
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
          ForEach(this.state.detail.tracks, (track: TrackListItem) => {
            ListItem() {
              SongListItem({
                item: track,
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
                onOpenActions: this.onOpenTrackActions
              })
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
}
