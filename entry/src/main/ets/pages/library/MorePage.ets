import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import {
  MORE_NAVIGATION_ITEMS,
  MoreNavigationItem
} from '../../components/navigation/MoreNavigation';

@Component
export struct MorePage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();
  openDestination: (routeId: string) => void = (_routeId: string) => {};

  build() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        ForEach(MORE_NAVIGATION_ITEMS, (item: MoreNavigationItem) => {
          Row({ space: 14 }) {
            SymbolGlyph(item.symbol)
              .fontSize(24)
              .fontColor([$r('app.color.theme_accent')])
            Column({ space: 3 }) {
              Text(item.label)
                .fontSize(17)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(item.description)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(18)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width('100%')
          .padding(18)
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
          .onClick(() => {
            this.openDestination(item.routeId);
          })
        }, (item: MoreNavigationItem) => item.routeId)
      }
      .width('100%')
      .padding({
        left: 24, right: 24,
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
