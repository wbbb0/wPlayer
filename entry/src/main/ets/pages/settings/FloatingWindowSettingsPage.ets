import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { SettingsToggleItem } from '../../components/settings/SettingsItem';
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
  private OpenBehaviorItem() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.square_fill_grid_2x2'))
        .fontSize(23)
        .fontColor([$r('app.color.theme_accent')])
      Column({ space: 3 }) {
        Text('打开浮窗后的行为')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('选择浮窗启动成功后如何处理主界面')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Select([
        { value: '什么也不做' },
        { value: '最小化应用' },
        { value: '关闭播放页面' }
      ])
        .selected(this.settingsStore.floatingWindowOpenBehavior)
        .value(FloatingWindowSettingsPolicy.openBehaviorLabel(
          this.settingsStore.floatingWindowOpenBehavior
        ))
        .onSelect((index: number): void => {
          this.settingsStore.setFloatingWindowOpenBehavior(index as FloatingWindowOpenBehavior);
          this.onSettingsChange();
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 76 })
    .padding({ left: 18, right: 14, top: 12, bottom: 12 })
  }

  @Builder
  private AutoCloseBehaviorItem() {
    Row({ space: 14 }) {
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(23)
        .fontColor([$r('app.color.theme_accent')])
      Column({ space: 3 }) {
        Text('何时自动关闭小窗')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('选择何时自动关闭专辑封面小窗')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Select([
        { value: '不自动关闭' },
        { value: '应用在前台时' },
        { value: '打开播放页面时' }
      ])
        .selected(this.settingsStore.floatingWindowAutoCloseBehavior)
        .value(FloatingWindowSettingsPolicy.autoCloseBehaviorLabel(
          this.settingsStore.floatingWindowAutoCloseBehavior
        ))
        .onSelect((index: number): void => {
          this.settingsStore.setFloatingWindowAutoCloseBehavior(
            index as FloatingWindowAutoCloseBehavior
          );
          this.onSettingsChange();
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 76 })
    .padding({ left: 18, right: 14, top: 12, bottom: 12 })
  }

  build() {
    Scroll(this.scroller) {
      Column() {
        Column() {
          this.OpenBehaviorItem()
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
          this.ItemDivider()
          this.AutoCloseBehaviorItem()
        }
        .width('100%')
        .borderRadius(20)
        .backgroundColor($r('app.color.glass_surface'))
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
