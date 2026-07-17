import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { ArtworkFitMode, ArtworkView } from '../../components/artwork/ArtworkView';
import { AlbumDetail, TrackListItem } from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { AppShellLayoutSpec } from '../../components/layout/AppShellLayoutSpec';
import { SongListItem, SongListItemLayout } from '../../components/library/SongListItem';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { DynamicColor, DynamicContainerRole } from '../../appearance/DynamicColor';

@Component
export struct AlbumDetailPage {
  @ObjectLink store: LibraryStore;
  @Prop albumId: number = -1;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @Prop showArtwork: boolean = true;
  @Prop themeBackground: string = '#FF000000';
  private multipleDiscTracks?: Array<TrackListItem>;
  private multipleDiscResult: boolean = false;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();

  aboutToAppear(): void {
    this.store.loadAlbumDetail(this.albumId);
  }

  private detail(): AlbumDetail | undefined {
    const detail = this.store.albumDetail;
    return detail !== undefined && detail.album.id === this.albumId ? detail : undefined;
  }

  private durationLabel(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private normalizedArtist(value: string): string {
    return value.trim().toLocaleLowerCase().replace(/\s+/g, ' ');
  }

  private showTrackArtist(track: TrackListItem, albumArtist: string): boolean {
    return track.artistDisplay.trim().length > 0 &&
      (albumArtist.trim().length === 0 ||
        this.normalizedArtist(track.artistDisplay) !== this.normalizedArtist(albumArtist));
  }

  private hasMultipleDiscs(tracks: Array<TrackListItem>): boolean {
    if (this.multipleDiscTracks === tracks) {
      return this.multipleDiscResult;
    }
    let firstDisc = -1;
    let hasUnknownDisc = false;
    for (let index = 0; index < tracks.length; index += 1) {
      const disc = tracks[index].discNumber;
      if (disc <= 0) {
        hasUnknownDisc = true;
        continue;
      }
      if (firstDisc < 0) {
        firstDisc = disc;
      } else if (disc !== firstDisc) {
        this.multipleDiscTracks = tracks;
        this.multipleDiscResult = true;
        return this.multipleDiscResult;
      }
    }
    this.multipleDiscTracks = tracks;
    this.multipleDiscResult = firstDisc >= 0 && hasUnknownDisc;
    return this.multipleDiscResult;
  }

  private isDiscStart(tracks: Array<TrackListItem>, index: number): boolean {
    if (!this.hasMultipleDiscs(tracks)) {
      return false;
    }
    return index === 0 || tracks[index - 1].discNumber !== tracks[index].discNumber;
  }

  private discLabel(discNumber: number): string {
    return discNumber > 0 ? `碟 ${discNumber}` : '碟号未知';
  }

  private playFirst(detail: AlbumDetail): void {
    if (detail.tracks.length > 0) {
      playbackRuntime.playInOrder(detail.tracks[0], detail.tracks);
    }
  }

  private usesWideHeader(): boolean {
    return this.rootWidth >= AppShellLayoutSpec.SIDE_NAVIGATION_BREAKPOINT;
  }

  private withAlpha(color: string, alpha: string): string {
    return color.length === 9 && color.startsWith('#') ? `#${alpha}${color.substring(3)}` : color;
  }

  @Builder
  private AlbumText(detail: AlbumDetail, centered: boolean) {
    Column({ space: 7 }) {
      Text(detail.album.title)
        .fontSize(centered ? 23 : 27)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(centered ? TextAlign.Center : TextAlign.Start)
        .maxLines(3)
        .width('100%')
      Text(detail.album.albumArtistDisplay.length > 0 ? detail.album.albumArtistDisplay : '未知专辑艺术家')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(centered ? TextAlign.Center : TextAlign.Start)
        .maxLines(2)
        .width('100%')
      Text(this.albumInformation(detail))
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(centered ? TextAlign.Center : TextAlign.Start)
        .width('100%')
    }
    .alignItems(centered ? HorizontalAlign.Center : HorizontalAlign.Start)
  }

  private albumInformation(detail: AlbumDetail): string {
    const values: Array<string> = [];
    if (detail.releaseYear > 0) {
      values.push(`${detail.releaseYear}`);
    }
    if (detail.genreDisplay.length > 0) {
      values.push(detail.genreDisplay);
    }
    values.push(`${detail.album.trackCount} 首`);
    values.push(this.durationLabel(detail.album.totalDurationMs));
    return values.join(' · ');
  }

  @Builder
  private HeaderArtwork(detail: AlbumDetail, size: number) {
    if (this.showArtwork) {
      ArtworkView({
        sourcePath: detail.album.artworkPath.length > 0 ?
          this.store.resolveArtworkPath(detail.album.artworkPath) : '',
        sourceWidth: detail.album.artworkWidth,
        sourceHeight: detail.album.artworkHeight,
        slotWidth: size,
        fitMode: ArtworkFitMode.CONTAIN,
        cornerRadius: 20,
        shadowEnabled: detail.album.artworkPath.length > 0
      })
    } else {
      Blank().width(size).height(size)
    }
  }

  @Builder
  private HeaderActionIcon(symbol: Resource, accent: string) {
    SymbolGlyph(symbol)
      .fontSize(20)
      .fontColor([DynamicColor.foreground(accent, DynamicContainerRole.ACCENT)])
  }

  @Builder
  private PlaybackActions(detail: AlbumDetail) {
    Row({ space: 12 }) {
      Button() {
        this.HeaderActionIcon($r('sys.symbol.shuffle'), detail.album.paletteAccent)
      }
      .width(44).height(44).borderRadius(22)
      .backgroundColor(this.withAlpha(detail.album.paletteAccent, '38'))
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .enabled(detail.tracks.length > 0)
      .accessibilityText('随机播放此专辑')
      .onClick(() => playbackRuntime.shuffleAll(detail.tracks))

      Button() {
        Row({ space: 7 }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(19).fontColor([
              DynamicColor.foreground(detail.album.paletteSecondary, DynamicContainerRole.SECONDARY)
            ])
          Text('播放').fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(DynamicColor.foreground(
              detail.album.paletteSecondary, DynamicContainerRole.SECONDARY
            ))
        }
      }
      .width(this.usesWideHeader() ? 220 : Math.min(220, Math.max(128, this.rootWidth - 164)))
      .height(44).backgroundColor(detail.album.paletteSecondary)
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .enabled(detail.tracks.length > 0)
      .onClick(() => this.playFirst(detail))

      Button() {
        this.HeaderActionIcon($r('sys.symbol.plus'), detail.album.paletteAccent)
      }
      .width(44).height(44).borderRadius(22)
      .backgroundColor(this.withAlpha(detail.album.paletteAccent, '38'))
      .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      .enabled(detail.tracks.length > 0)
      .accessibilityText('添加到队列')
      .onClick(() => playbackRuntime.appendToQueue(detail.tracks))
    }
    .width('100%')
    .justifyContent(this.usesWideHeader() ? FlexAlign.Start : FlexAlign.Center)
  }

  @Builder
  private Header(detail: AlbumDetail) {
    Column({ space: 18 }) {
      if (this.usesWideHeader()) {
        Row({ space: 28 }) {
          this.HeaderArtwork(detail, 184)
          Column({ space: 20 }) {
            this.AlbumText(detail, false)
            this.PlaybackActions(detail)
          }
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      } else {
        Column({ space: 16 }) {
          this.HeaderArtwork(detail, Math.min(220, Math.max(156, this.rootWidth - 112)))
          this.AlbumText(detail, true)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        this.PlaybackActions(detail)
      }
    }
    .width('100%')
    .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET, bottom: 14 })
  }

  build() {
    List({ space: 2, scroller: this.scroller }) {
      if (this.albumId === this.store.albumDetail?.album.id && this.store.albumDetail !== undefined) {
        ListItem() { this.Header(this.store.albumDetail) }
        ForEach(this.store.albumDetail.tracks, (track: TrackListItem, index: number) => {
          ListItem() {
            Column() {
              if (this.isDiscStart(this.store.albumDetail!.tracks, index)) {
                Row({ space: 10 }) {
                  Text(this.discLabel(track.discNumber))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_secondary'))
                  Divider().layoutWeight(1).color($r('app.color.text_tertiary')).opacity(0.3)
                }
                .width('100%')
                .padding({ left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET,
                  top: 12, bottom: 5 })
              } else if (index > 0) {
                Divider().color($r('app.color.text_tertiary')).opacity(0.3)
                  .margin({ left: PageLayoutSpec.HORIZONTAL_INSET + 42,
                    right: PageLayoutSpec.HORIZONTAL_INSET })
              }
              SongListItem({
                item: track,
                layout: SongListItemLayout.ALBUM,
                trackNumber: track.trackNumber,
                showArtist: this.showTrackArtist(
                  track,
                  this.store.albumDetail!.album.albumArtistDisplay
                ),
                actionTrack: track,
                horizontalInset: PageLayoutSpec.HORIZONTAL_INSET,
                verticalInset: 0,
                minimumHeight: 58,
                rowCornerRadius: 14,
                queueIndexWidth: 30,
                onActivate: (): void => {
                  const detail = this.detail();
                  if (detail !== undefined) {
                    playbackRuntime.playInOrder(track, detail.tracks);
                  }
                }
              })
            }
          }
        }, (track: TrackListItem) => `${track.id}`)
      } else if (this.store.albumDetailLoading) {
        ListItem() { LoadingProgress().width(40).height(40).margin({ top: 72 }) }
      } else {
        ListItem() {
          Text(this.store.albumDetailError.length > 0 ? this.store.albumDetailError : '正在载入专辑…')
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
    .backgroundColor(this.themeBackground)
    .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
  }
}
