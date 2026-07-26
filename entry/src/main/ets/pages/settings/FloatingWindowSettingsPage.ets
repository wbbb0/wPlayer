import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import {
  SettingsSelectItem,
  SettingsToggleItem
} from '../../components/settings/SettingsItem';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import {
  FloatingWindowAutoCloseBehavior,
  FloatingWindowOpenBehavior,
  FloatingWindowSettingsPolicy
} from '../../settings/FloatingWindowSettingsPolicy';

@Component
export struct FloatingWindowSettingsPage {
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  onSettingsChange: () => void = (): void => {};

  @Builder
  private ItemDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.text_tertiary'))
      .opacity(0.28)
      .margin({ left: 56, right: 16 })
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 4, bottom: 10 })
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 22 }) {
        Column() {
          this.SectionTitle('打开与启动')
          Column() {
            SettingsSelectItem({
              imageSource: $r('app.media.control_picture_in_picture'),
              title: '打开浮窗后的行为',
              description: '选择浮窗启动成功后如何处理主界面',
              options: ['什么也不做', '最小化应用', '关闭播放页面'],
              selected: this.settingsStore.floatingWindowOpenBehavior,
              value: FloatingWindowSettingsPolicy.openBehaviorLabel(
                this.settingsStore.floatingWindowOpenBehavior
              ),
              onSelect: (index: number): void => {
                this.settingsStore.setFloatingWindowOpenBehavior(
                  index as FloatingWindowOpenBehavior
                );
                this.onSettingsChange();
              }
            })
            this.ItemDivider()
            SettingsToggleItem({
              symbol: $r('sys.symbol.play_fill'),
              title: '播放时最小化自动打开浮窗',
              description: '正在播放时最小化应用，自动显示专辑封面浮窗',
              isOn: this.settingsStore.floatingWindowAutoStartOnMinimize,
              onChange: (value: boolean): void => {
                this.settingsStore.setFloatingWindowAutoStartOnMinimize(value);
                this.onSettingsChange();
              }
            })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
        }
        .width('100%')

        Column() {
          this.SectionTitle('关闭')
          Column() {
            SettingsSelectItem({
              symbol: $r('sys.symbol.xmark'),
              title: '何时自动关闭小窗',
              description: '选择何时自动关闭专辑封面小窗',
              options: ['不自动关闭', '应用在前台时', '打开播放页面时'],
              selected: this.settingsStore.floatingWindowAutoCloseBehavior,
              value: FloatingWindowSettingsPolicy.autoCloseBehaviorLabel(
                this.settingsStore.floatingWindowAutoCloseBehavior
              ),
              onSelect: (index: number): void => {
                this.settingsStore.setFloatingWindowAutoCloseBehavior(
                  index as FloatingWindowAutoCloseBehavior
                );
                this.onSettingsChange();
              }
            })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
        }
        .width('100%')
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
