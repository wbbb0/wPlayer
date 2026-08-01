import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from
  '../../components/layout/PageScrollBehavior';
import { SettingsToggleItem } from '../../components/settings/SettingsItem';
import { AppSettingsStore } from '../../settings/AppSettingsStore';

@Component
export struct PlayerPageSettingsPage {
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  onKeepScreenOnChange: () => void = (): void => {};

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
      Column() {
        this.SectionTitle('显示')
        Column() {
          SettingsToggleItem({
            symbol: $r('sys.symbol.sun_max_fill'),
            title: '保持屏幕常亮',
            description: '打开播放页面时，阻止屏幕自动熄灭',
            isOn: this.settingsStore.playerPageKeepScreenOn,
            onChange: (value: boolean): void => {
              this.settingsStore.setPlayerPageKeepScreenOn(value);
              this.onKeepScreenOnChange();
            }
          })
          this.ItemDivider()
          SettingsToggleItem({
            imageSource: $r('app.media.control_picture_in_picture'),
            title: '显示浮窗按钮',
            description: '在播放页面显示专辑封面浮窗入口',
            isOn: this.settingsStore.playerPageShowFloatingWindowButton,
            onChange: (value: boolean): void =>
              this.settingsStore.setPlayerPageShowFloatingWindowButton(value)
          })
          this.ItemDivider()
          SettingsToggleItem({
            symbol: $r('sys.symbol.lyrics_square'),
            title: '歌词模糊效果',
            description: '自动跟随歌词时，模糊非当前歌词',
            isOn: this.settingsStore.playerPageLyricBlurEffect,
            onChange: (value: boolean): void =>
              this.settingsStore.setPlayerPageLyricBlurEffect(value)
          })
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
