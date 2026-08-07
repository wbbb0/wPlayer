import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { SettingsToggleItem } from '../../components/settings/SettingsItem';
import { AppSettingsStore } from '../../settings/AppSettingsStore';

@Component
export struct DebugPage {
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
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
