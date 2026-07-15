import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageListBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryAlphabetIndex } from '../../components/library/LibraryAlphabetIndex';
import { ArtworkFitMode, ArtworkView } from '../../components/artwork/ArtworkView';
import {
  LibraryIndexPresentation,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct SongsPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  onPlayTrack: (item: TrackListItem) => void = (_item: TrackListItem): void => {};
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageListBehavior = new PageListBehavior();
  @Builder
  private EmptyState() {
    ListItem() {
      Column({ space: 10 }) {
        if (this.store.loading) {
          LoadingProgress().width(36).height(36)
        } else {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(42)
            .fontColor([$r('app.color.text_tertiary')])
          Text('还没有音乐')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('可在“更多 → 音乐库”中添加 MP3 或 FLAC')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .padding({ top: 64, left: PageLayoutSpec.HORIZONTAL_INSET, right: PageLayoutSpec.HORIZONTAL_INSET })
    }
  }

  build() {
    Stack({ alignContent: Alignment.End }) {
      List({ space: 4, scroller: this.scroller }) {
        if (this.store.statistics.trackCount === 0) {
          this.EmptyState()
        } else {
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
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .borderRadius(16)
              .backgroundColor($r('app.color.glass_surface_subtle'))
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                this.onPlayTrack(item);
              })
            }
            .padding({ left: 12, right: 12 })
          }, (item: TrackListItem) => `${item.id}`)
        }
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
