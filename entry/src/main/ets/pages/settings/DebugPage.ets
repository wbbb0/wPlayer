import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { SettingsLinkItem, SettingsToggleItem } from '../../components/settings/SettingsItem';
import { AppSettingsStore } from '../../settings/AppSettingsStore';

@Component
export struct DebugPage {
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  openDynamicBackgroundV1: () => void = (): void => {};
  openDynamicBackgroundV2: () => void = (): void => {};
  openDynamicBackgroundV3: () => void = (): void => {};
  onDemoLibraryChange: (value: boolean) => void = (_value: boolean): void => {};

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 6, bottom: 8 })
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 20 }) {
        Column() {
          this.SectionTitle('数据')
          Column() {
            SettingsToggleItem({
              symbol: $r('sys.symbol.opticaldisc'),
              title: '演示音乐库',
              description: '显示截图用虚构歌曲、播放列表、歌词和播放队列',
              isOn: this.settingsStore.demoLibraryEnabled,
              onChange: this.onDemoLibraryChange
            })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
        }

        Column() {
          this.SectionTitle('视觉效果')
          Column() {
            SettingsLinkItem({
              symbol: $r('sys.symbol.square_fill_grid_2x2'),
              title: '动态背景 v1',
              description: '双层预处理纹理漂移与 GPU 合成',
              onActivate: this.openDynamicBackgroundV1
            })
            SettingsLinkItem({
              symbol: $r('sys.symbol.square_fill_grid_2x2'),
              title: '动态背景 v2',
              description: '参考网页的四层 Sprite、Twist、Blur 与饱和度实现',
              onActivate: this.openDynamicBackgroundV2
            })
            SettingsLinkItem({
              symbol: $r('sys.symbol.square_fill_grid_2x2'),
              title: '动态背景 v3',
              description: '基于 aadishv/html-music 参考参数的低分辨率原生 GPU 实现',
              onActivate: this.openDynamicBackgroundV3
            })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
        }
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
    .backgroundColor(Color.Transparent)
    .attributeModifier(new PageScrollBehavior())
  }
}
