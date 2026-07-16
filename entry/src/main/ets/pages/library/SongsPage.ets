import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryAlphabetIndex } from '../../components/library/LibraryAlphabetIndex';
import { LibraryEmptyState } from '../../components/library/LibraryEmptyState';
import { ArtworkFitMode, ArtworkView } from '../../components/artwork/ArtworkView';
import {
  LibraryIndexPresentation,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { QueueActionMenu } from '../../components/library/QueueActionMenu';

enum SongRowFeedbackPhase {
  IDLE,
  HIGHLIGHTING,
  RETURNING
}

class SongRowMotionSpec {
  static readonly HIGHLIGHT_DURATION: number = 55;
  static readonly RETURN_DURATION: number = 140;
}

@Component
export struct SongsPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State rowFeedbackTrackId: number = -1;
  @State rowFeedbackPhase: SongRowFeedbackPhase = SongRowFeedbackPhase.IDLE;
  onPlayTrack: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();
  private rowFeedbackEpoch: number = 0;

  private durationLabel(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private beginRowFeedback(trackId: number): void {
    const epoch = ++this.rowFeedbackEpoch;
    this.getUIContext().animateTo({
      duration: SongRowMotionSpec.HIGHLIGHT_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.finishRowFeedback(epoch);
      }
    }, () => {
      this.rowFeedbackTrackId = trackId;
      this.rowFeedbackPhase = SongRowFeedbackPhase.HIGHLIGHTING;
    });
  }

  private finishRowFeedback(epoch: number): void {
    if (epoch !== this.rowFeedbackEpoch) {
      return;
    }
    this.rowFeedbackPhase = SongRowFeedbackPhase.RETURNING;
    this.getUIContext().animateTo({
      duration: SongRowMotionSpec.RETURN_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (epoch === this.rowFeedbackEpoch) {
          this.rowFeedbackPhase = SongRowFeedbackPhase.IDLE;
        }
      }
    }, () => {
      this.rowFeedbackTrackId = -1;
    });
  }

  private isRowHighlighted(trackId: number): boolean {
    return this.rowFeedbackTrackId === trackId &&
      this.rowFeedbackPhase !== SongRowFeedbackPhase.IDLE;
  }

  build() {
    if (this.store.statistics.trackCount === 0) {
      LibraryEmptyState({
        symbol: $r('sys.symbol.music_fill'),
        title: '还没有音乐',
        description: '可在“更多 → 音乐库”中添加 MP3 或 FLAC',
        loading: this.store.loading,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        scroller: this.scroller
      })
    } else {
      Stack({ alignContent: Alignment.End }) {
        List({ space: 4, scroller: this.scroller }) {
          LazyForEach(this.store.trackDataSource, (item: TrackListItem) => {
            ListItem() {
              Row({ space: 12 }) {
                ArtworkView({
                  sourcePath: item.artworkPath.length > 0 ? this.store.resolveArtworkPath(item.artworkPath) : '',
                  sourceWidth: item.artworkWidth,
                  sourceHeight: item.artworkHeight,
                  slotWidth: 52,
                  fitMode: ArtworkFitMode.CONTAIN,
                  cornerRadius: 10
                })
                Column({ space: 4 }) {
                  Text(item.title)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                  Text(item.artistDisplay.length > 0 ? item.artistDisplay : '未知艺术家')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text(this.durationLabel(item.durationMs))
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
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
                .accessibilityText('更多歌曲操作')
                .bindMenu(QueueActionMenu([item]), { placement: Placement.BottomRight })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor(this.isRowHighlighted(item.id) ?
                $r('app.color.glass_surface_strong') : $r('app.color.glass_surface_subtle'))
              .hoverEffect(HoverEffect.None)
              .onClick(() => {
                this.beginRowFeedback(item.id);
                this.onPlayTrack(item);
              })
            }
            .padding({ left: 12, right: 12 })
          }, (item: TrackListItem) => `${item.id}`)
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(PageLayoutSpec.primaryContentStart(this.topInset))
        .contentEndOffset(PageLayoutSpec.contentEnd(this.bottomInset))
        .scrollBar(this.store.trackIndexPresentation === LibraryIndexPresentation.ALPHABET ?
          BarState.Off : BarState.Auto)
        .attributeModifier(this.scrollBehavior)

        if (this.store.trackIndexPresentation === LibraryIndexPresentation.ALPHABET &&
          this.store.trackSections.length > 0) {
          LibraryAlphabetIndex({
            sections: this.store.trackSections,
            onSelect: (itemIndex: number) => {
              this.scroller.scrollToIndex(itemIndex, false, ScrollAlign.START);
            }
          })
          .margin({ right: 2, bottom: PageLayoutSpec.contentEnd(this.bottomInset) / 2 })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
  }
}
