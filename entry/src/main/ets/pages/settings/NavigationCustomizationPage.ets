import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import {
  NavigationPageItem,
  PRIMARY_NAVIGATION_COUNT
} from '../../components/navigation/MoreNavigation';

@Component
export struct NavigationCustomizationPage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop items: Array<NavigationPageItem> = [];
  scroller: Scroller = new Scroller();
  onMove: (from: number, to: number) => void = (_from: number, _to: number): void => {};

  build() {
    List({ scroller: this.scroller, space: 8 }) {
      ForEach(this.items, (item: NavigationPageItem, index: number) => {
        ListItem() {
          Row({ space: 14 }) {
            SymbolGlyph(item.symbol)
              .fontSize(23)
              .fontColor([$r('app.color.theme_accent')])
            Column({ space: 3 }) {
              Text(item.label)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(index < PRIMARY_NAVIGATION_COUNT ? '显示在导航栏' : '显示在更多')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            SymbolGlyph($r('sys.symbol.line_3_horizontal'))
              .fontSize(20)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 15, bottom: 15 })
          .borderRadius(18)
          .backgroundColor($r('app.color.glass_surface'))
        }
      }, (item: NavigationPageItem) => item.routeId)
      .onMove(this.onMove)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 24,
      right: 24,
      top: PageLayoutSpec.secondaryContentStart(this.topInset),
      bottom: PageLayoutSpec.contentEnd(this.bottomInset)
    })
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor(Color.Transparent)
  }
}
