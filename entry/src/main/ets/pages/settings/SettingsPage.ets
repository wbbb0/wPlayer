import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';
import { SettingsLinkItem, SettingsToggleItem } from '../../components/settings/SettingsItem';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { CompletedCollectionMode } from '../../playback/model/PlaybackModels';
import { CompletedCollectionSettingPolicy } from '../../settings/CompletedCollectionSettingPolicy';
import BuildProfile from 'entry/BuildProfile';

@Component
export struct SettingsPage {
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  scroller: Scroller = new Scroller();
  openNavigationCustomization: () => void = (): void => {};
  openAbout: () => void = (): void => {};
  openPrivacyPolicy: () => void = (): void => {};
  openDataAndPermissions: () => void = (): void => {};
  openOpenSourceLicenses: () => void = (): void => {};
  onRememberLastTabChange: (value: boolean) => void = (_value: boolean): void => {};
  onRememberSortChange: (value: boolean) => void = (_value: boolean): void => {};
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
              symbol: $r('sys.symbol.headphones'),
              title: '耳机重连后自动续播',
              description: '因输出设备断开暂停后，5 分钟内重连才自动继续播放',
              isOn: this.settingsStore.autoResumeAfterOutputReconnect,
              onChange: (value: boolean): void => this.settingsStore.setAutoResumeAfterOutputReconnect(value)
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
            SettingsToggleItem({
              symbol: $r('sys.symbol.trash'),
              title: '自动移除失效文件',
              description: '播放时发现文件不可用即移除音乐库记录，不会删除原始文件',
              isOn: this.settingsStore.autoRemoveUnavailableOnPlayback,
              onChange: (value: boolean): void =>
                this.settingsStore.setAutoRemoveUnavailableOnPlayback(value)
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

        if (BuildProfile.DEBUG) {
          Column() {
            this.SectionTitle('调试')
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

        Column() {
          this.SectionTitle('关于')
          Column() {
            SettingsLinkItem({
              symbol: $r('sys.symbol.music_fill'),
              title: '关于 w播放器',
              description: '应用信息、开发者与联系方式',
              onActivate: this.openAbout
            })
            this.ItemDivider()
            SettingsLinkItem({
              symbol: $r('sys.symbol.checkmark_circle_fill'),
              title: '隐私政策',
              description: '了解本地音乐和应用数据如何处理',
              onActivate: this.openPrivacyPolicy
            })
            this.ItemDivider()
            SettingsLinkItem({
              symbol: $r('sys.symbol.externaldrive_fill'),
              title: '数据与权限',
              description: '查看本地数据、系统权限与删除方式',
              onActivate: this.openDataAndPermissions
            })
            this.ItemDivider()
            SettingsLinkItem({
              symbol: $r('sys.symbol.list_bullet'),
              title: '开源软件许可',
              description: 'GPL-3.0-only 许可与对应源代码',
              onActivate: this.openOpenSourceLicenses
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
