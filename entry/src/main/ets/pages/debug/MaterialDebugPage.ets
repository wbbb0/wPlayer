import { PageLayoutSpec } from '../../components/layout/PageLayoutSpec';
import { PageScrollBehavior, PageScrollContentBehavior } from '../../components/layout/PageScrollBehavior';

interface BlurSample {
  label: string;
  detail: string;
  style: BlurStyle;
}

@Component
export struct MaterialDebugPage {
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @State selectedOption: number = 0;
  @State showPopup: boolean = false;
  @State showSheet: boolean = false;
  scroller: Scroller = new Scroller();
  private readonly scrollBehavior: PageScrollBehavior = new PageScrollBehavior();
  private readonly contentBehavior: PageScrollContentBehavior = new PageScrollContentBehavior();
  private readonly blurSamples: Array<BlurSample> = [
    { label: 'Ultra Thin', detail: 'COMPONENT_ULTRA_THIN', style: BlurStyle.COMPONENT_ULTRA_THIN },
    { label: 'Thin', detail: 'COMPONENT_THIN', style: BlurStyle.COMPONENT_THIN },
    { label: 'Regular', detail: 'COMPONENT_REGULAR', style: BlurStyle.COMPONENT_REGULAR },
    { label: 'Thick', detail: 'COMPONENT_THICK', style: BlurStyle.COMPONENT_THICK },
    { label: 'Ultra Thick', detail: 'COMPONENT_ULTRA_THICK', style: BlurStyle.COMPONENT_ULTRA_THICK }
  ];

  @Builder
  private SectionTitle(title: string, description: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text(description)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private MaterialCard(sample: BlurSample) {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Text('A')
          .fontSize(74)
          .fontWeight(FontWeight.Bold)
          .fontColor('#CCFFFFFF')
        Blank()
        SymbolGlyph($r('sys.symbol.music_fill'))
          .fontSize(66)
          .fontColor(['#CCFFFFFF'])
      }
      .width('100%')
      .height('100%')
      .padding({ left: 18, right: 18 })
      .linearGradient({
        angle: 132,
        colors: [['#FFE86A92', 0], ['#FF7A5CFA', 0.48], ['#FF21B8C7', 1]]
      })

      Column({ space: 4 }) {
        Text(sample.label)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFF8F8F8')
        Text(sample.detail)
          .fontSize(10)
          .fontColor('#CCFFFFFF')
      }
      .width('78%')
      .height(78)
      .justifyContent(FlexAlign.Center)
      .borderRadius(22)
      .backgroundBlurStyle(sample.style, {
        adaptiveColor: AdaptiveColor.AVERAGE,
        policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
        scale: 1
      })
      .outline({ width: 1, color: '#29FFFFFF' })
      .shadow(ShadowStyle.OUTER_DEFAULT_SM)
    }
    .width('100%')
    .height(142)
    .borderRadius(26)
    .clip(true)
  }

  @Builder
  private PopupContent() {
    Column({ space: 8 }) {
      Text('Custom Popup')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text('Popup 背板使用 COMPONENT_ULTRA_THICK')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
    .padding(18)
  }

  @Builder
  private SheetContent() {
    Column({ space: 14 }) {
      Text('Glass Sheet')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      Text('bindSheet 在 API 24 可以使用 blurStyle。拖动或点击关闭按钮返回。')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Button('完成')
        .width('100%')
        .onClick(() => this.showSheet = false)
    }
    .width('100%')
    .padding(24)
  }

  private showGlassDialog(): void {
    this.getUIContext().showAlertDialog({
      title: 'Glass Dialog',
      message: 'AlertDialog 使用透明背景与 COMPONENT_ULTRA_THICK 背板材质。',
      confirm: {
        value: '知道了',
        action: () => {}
      },
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      backgroundBlurStyleOptions: {
        adaptiveColor: AdaptiveColor.AVERAGE,
        policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
        scale: 1
      }
    });
  }

  @Builder
  private InteractiveSamples() {
    Column({ space: 12 }) {
      Select([
        { value: 'Ultra Thin' },
        { value: 'Regular' },
        { value: 'Ultra Thick' }
      ])
        .selected(this.selectedOption)
        .value('Select 下拉菜单')
        .width('100%')
        .menuBackgroundColor(Color.Transparent)
        .menuBackgroundBlurStyle(BlurStyle.COMPONENT_ULTRA_THICK)
        .onSelect((index: number) => this.selectedOption = index)

      Button('打开 Menu')
        .width('100%')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .bindMenu([
          { value: '按名称排序', action: () => {} },
          { value: '按艺术家排序', action: () => {} },
          { value: '按添加时间排序', action: () => {} }
        ], {
          backgroundColor: Color.Transparent,
          backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
          backgroundBlurStyleOptions: {
            adaptiveColor: AdaptiveColor.AVERAGE,
            policy: BlurStyleActivePolicy.ALWAYS_ACTIVE,
            scale: 1
          },
          borderRadius: 20,
          outlineWidth: 1,
          outlineColor: '#29FFFFFF'
        })

      Button('打开 Popup')
        .width('100%')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick(() => this.showPopup = true)
        .bindPopup(this.showPopup, {
          builder: this.PopupContent,
          popupColor: Color.Transparent,
          backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
          radius: 20,
          enableArrow: true,
          placement: Placement.Bottom,
          onStateChange: (event) => this.showPopup = event.isVisible
        })

      Button('打开 Sheet')
        .width('100%')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick(() => this.showSheet = true)

      Button('打开 Dialog')
        .width('100%')
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick(() => this.showGlassDialog())
    }
    .width('100%')
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 18 }) {
        this.SectionTitle('HDS 沉浸光感',
          '当前页面标题栏与应用悬浮 Tabs 是 API 24 公开支持的 systemMaterialEffect 入口。')

        Column({ space: 6 }) {
          Text('API 24 的公开 HDS 范围')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('HdsNavigation / HdsNavDestination 标题栏按钮\nHdsTabs 悬浮页签与 MiniBar')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .width('100%')
        .padding(18)
        .borderRadius(20)
        .backgroundColor($r('app.color.glass_surface'))

        this.SectionTitle('BlurStyle 对比', '下面五张卡片使用相同底图，只改变 ArkUI 组件材质厚度。')
        ForEach(this.blurSamples, (sample: BlurSample) => {
          this.MaterialCard(sample)
        }, (sample: BlurSample) => sample.detail)

        this.SectionTitle('弹出组件', '点击后直接比较 Select、Menu、Popup、Sheet 和 Dialog 的系统背板。')
        this.InteractiveSamples()

        Text('API 26 的 ImmersiveMaterial、menuSystemMaterial 与通用 systemMaterial 未加入此页，避免在当前 API 24 工程中使用不可用接口。')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      .width('100%')
      .padding({
        left: PageLayoutSpec.HORIZONTAL_INSET,
        right: PageLayoutSpec.HORIZONTAL_INSET,
        top: PageLayoutSpec.secondaryContentStart(this.topInset),
        bottom: PageLayoutSpec.contentEnd(this.bottomInset)
      })
      .attributeModifier(this.contentBehavior)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .attributeModifier(this.scrollBehavior)
    .bindSheet($$this.showSheet, this.SheetContent(), {
      height: SheetSize.MEDIUM,
      showClose: true,
      dragBar: true,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK
    })
  }
}
