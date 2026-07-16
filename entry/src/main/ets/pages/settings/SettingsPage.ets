import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';

@Component
export struct SettingsPage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  openNavigationCustomization: () => void = (): void => {};

  build() {
    Scroll(this.scroller) {
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontSize(24)
            .fontColor([$r('app.color.theme_accent')])
          Column({ space: 3 }) {
            Text('自定义页面')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('调整导航栏与“更多”中的页面顺序')
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
        .onClick(this.openNavigationCustomization)
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: PageLayoutSpec.primaryContentStart(this.topInset),
        bottom: PageLayoutSpec.contentEnd(this.bottomInset)
      })
      .attributeModifier(new PageScrollContentBehavior())
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .attributeModifier(new PageScrollBehavior())
  }
}
