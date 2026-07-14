import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import {
  PageContentAlignment,
  PageScrollBehavior,
  PageScrollContentBehavior
} from '../../components/layout/PageScrollBehavior';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct PlaylistsPage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior =
    new PageScrollContentBehavior(PageContentAlignment.CENTER);

  build() {
    Scroll(this.scroller) {
      Column({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(42)
          .fontColor([$r('app.color.text_tertiary')])
        Text('还没有播放列表')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('播放列表功能将在播放链路完成后接入')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({
        left: PageLayoutSpec.HORIZONTAL_INSET,
        right: PageLayoutSpec.HORIZONTAL_INSET,
        top: PageLayoutSpec.primaryContentStart(this.topInset),
        bottom: PageLayoutSpec.contentEnd(this.bottomInset)
      })
      .attributeModifier(this.contentBehavior)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .attributeModifier(this.scrollBehavior)
  }
}
