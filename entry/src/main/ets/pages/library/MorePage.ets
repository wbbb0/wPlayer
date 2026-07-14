import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { LibraryStore } from '../../library/store/LibraryStore';

@Component
export struct MorePage {
  @ObjectLink store: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();
  openLibraryManagement: () => void = () => {};

  build() {
    Scroll(this.scroller) {
      Column() {
        Row({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.externaldrive_fill'))
            .fontSize(24)
            .fontColor([$r('app.color.theme_accent')])
          Column({ space: 3 }) {
            Text('音乐库管理')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text('添加 MP3 / FLAC，查看统计或清空测试数据')
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
          this.openLibraryManagement();
        })
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
