import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { SettingsLinkItem, SettingsToggleItem } from '../../components/settings/SettingsItem';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { CompletedCollectionMode } from '../../playback/model/PlaybackModels';
import { CompletedCollectionSettingPolicy } from '../../settings/CompletedCollectionSettingPolicy';

@Component
export struct SettingsPage {
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  openNavigationCustomization: () => void = (): void => {};
  onRememberLastTabChange: (value: boolean) => void = (_value: boolean): void => {};
  onRememberSortChange: (value: boolean) => void = (_value: boolean): void => {};

  @Builder
  private SectionTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .padding({ left: 6, bottom: 8 })
  }

  @Builder
  private ItemDivider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('app.color.text_tertiary'))
      .opacity(0.28)
      .margin({ left: 56, right: 16 })
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 20 }) {
        Column() {
          this.SectionTitle('外观')
          Column() {
            SettingsToggleItem({
              symbol: $r('sys.symbol.opticaldisc'),
              title: '高质量主封面',
              description: '播放页主封面使用高质量缩放，可能增加渲染开销',
              isOn: this.settingsStore.highQualityHeroArtwork,
              onChange: (value: boolean): void => this.settingsStore.setHighQualityHeroArtwork(value)
            })
            this.ItemDivider()
            SettingsToggleItem({
              symbol: $r('sys.symbol.square_fill_grid_2x2'),
              title: '播放主题融入背景',
              description: '使用当前歌曲的主题色轻微着色应用背景',
              isOn: this.settingsStore.followPlaybackTheme,
              onChange: (value: boolean): void => this.settingsStore.setFollowPlaybackTheme(value)
            })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
        }

        Column() {
          this.SectionTitle('播放')
          Column() {
            SettingsToggleItem({
              symbol: $r('sys.symbol.play_fill'),
              title: '记住播放进度',
              description: '再次播放上次的歌曲时，从保存的位置继续',
              isOn: this.settingsStore.rememberPlaybackPosition,
              onChange: (value: boolean): void => this.settingsStore.setRememberPlaybackPosition(value)
            })
            this.ItemDivider()
            SettingsToggleItem({
              symbol: $r('sys.symbol.shuffle'),
              title: '保留随机播放状态',
              description: '从普通播放入口开始播放时，不自动关闭随机播放',
              isOn: this.settingsStore.preserveShuffleOnManualPlay,
              onChange: (value: boolean): void => this.settingsStore.setPreserveShuffleOnManualPlay(value)
            })
            this.ItemDivider()
            Row({ space: 14 }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(23)
                .fontColor([$r('app.color.theme_accent')])
              Column({ space: 3 }) {
                Text('完整听过收集')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                Text('设置新播放队列是否自动开启收集')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(2)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Select([
                { value: '智能' },
                { value: '默认开启' },
                { value: '默认关闭' }
              ])
                .selected(this.settingsStore.completedCollectionMode)
                .value(CompletedCollectionSettingPolicy.label(this.settingsStore.completedCollectionMode))
                .onSelect((index: number) => {
                  this.settingsStore.setCompletedCollectionMode(index as CompletedCollectionMode);
                })
            }
            .width('100%')
            .constraintSize({ minHeight: 76 })
            .padding({ left: 18, right: 14, top: 12, bottom: 12 })
          }
          .width('100%')
          .borderRadius(20)
          .backgroundColor($r('app.color.glass_surface'))
        }

        Column() {
          this.SectionTitle('记忆与导航')
          Column() {
            SettingsToggleItem({
              symbol: $r('sys.symbol.music_fill'),
              title: '记住上次页面',
              description: '下次打开应用时，返回上次使用的页面',
              isOn: this.settingsStore.rememberLastTab,
              onChange: this.onRememberLastTabChange
            })
            this.ItemDivider()
            SettingsToggleItem({
              symbol: $r('sys.symbol.list_bullet'),
              title: '记住排序方式',
              description: '保留歌曲与专辑上次使用的排序字段和方向',
              isOn: this.settingsStore.rememberLibrarySort,
              onChange: this.onRememberSortChange
            })
            this.ItemDivider()
            SettingsLinkItem({
              symbol: $r('sys.symbol.list_bullet'),
              title: '自定义页面',
              description: '调整导航栏与“更多”中的页面顺序',
              onActivate: this.openNavigationCustomization
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
