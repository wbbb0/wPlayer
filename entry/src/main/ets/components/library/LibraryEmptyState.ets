import { PageLayoutSpec } from '../layout/PageLayoutSpec';
import {
  PageContentAlignment,
  PageScrollBehavior,
  PageScrollContentBehavior
} from '../layout/PageScrollBehavior';

@Component
export struct LibraryEmptyState {
  @Prop symbol: Resource = $r('sys.symbol.music_fill');
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop loading: boolean = false;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior =
    new PageScrollContentBehavior(PageContentAlignment.CENTER);

  build() {
    Scroll(this.scroller) {
      Column({ space: 10 }) {
        if (this.loading) {
          LoadingProgress()
            .width(36)
            .height(36)
        } else {
          SymbolGlyph(this.symbol)
            .fontSize(42)
            .fontColor([$r('app.color.text_tertiary')])
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.description)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
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
    .backgroundColor(Color.Transparent)
    .attributeModifier(this.scrollBehavior)
  }
}
