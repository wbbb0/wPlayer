import { DynamicBackgroundV3NativeContext } from 'libwplayerbackground.so';
import { DynamicBackgroundArtworkCoordinator } from
  '../../components/player/DynamicBackgroundArtworkCoordinator';
import { DynamicBackgroundV3Spec } from '../../components/player/DynamicBackgroundV3Spec';
import { PlayerStore } from '../../playback/model/PlaybackModels';

@Component
struct DynamicBackgroundV3Slider {
  @Prop title: string = '';
  @Prop valueText: string = '';
  @Prop value: number = 0;
  @Prop minimum: number = 0;
  @Prop maximum: number = 1;
  @Prop step: number = 0.01;
  onChange: (value: number) => void = (_value: number): void => {};

  build() {
    Column({ space: 3 }) {
      Row() {
        Text(this.title)
          .fontSize(12)
          .fontColor('#FFFFFFFF')
        Blank()
        Text(this.valueText)
          .fontSize(12)
          .fontColor('#B8FFFFFF')
      }
      .width('100%')

      Slider({
        value: this.value,
        min: this.minimum,
        max: this.maximum,
        step: this.step,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .selectedColor('#FFFFFFFF')
        .trackColor('#4DFFFFFF')
        .blockColor('#FFFFFFFF')
        .onChange((value: number, _mode: SliderChangeMode): void => this.onChange(value))
    }
    .width('100%')
  }
}

@Component
export struct DynamicBackgroundV3DebugPage {
  @ObjectLink @Watch('onPlayerStoreChanged') playerStore: PlayerStore;
  @Prop bottomInset: number = 0;
  @State private speed: number = DynamicBackgroundV3Spec.DEFAULT_SPEED;
  @State private controlsVisible: boolean = true;
  @State private animationPaused: boolean = false;
  private readonly artworkCoordinator: DynamicBackgroundArtworkCoordinator =
    new DynamicBackgroundArtworkCoordinator('DynamicBackgroundV3Debug');
  private pageVisible: boolean = false;
  private artworkSyncScheduled: boolean = false;

  aboutToAppear(): void {
    this.pageVisible = true;
    this.artworkCoordinator.activate(this.playerStore);
    this.artworkCoordinator.setPaused(this.animationPaused);
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.artworkCoordinator.deactivate();
  }

  onDidBuild(): void {
    this.artworkCoordinator.sync();
  }

  private onPlayerStoreChanged(): void {
    if (this.artworkSyncScheduled) {
      return;
    }
    this.artworkSyncScheduled = true;
    Promise.resolve().then((): void => {
      this.artworkSyncScheduled = false;
      if (this.pageVisible) {
        this.artworkCoordinator.sync();
      }
    });
  }

  private currentTrackTitle(): string {
    return this.playerStore.currentTrack?.title ?? '没有正在播放的歌曲';
  }

  private toggleAnimation(): void {
    this.animationPaused = !this.animationPaused;
    this.artworkCoordinator.setPaused(this.animationPaused);
  }

  private resetParameters(): void {
    this.speed = DynamicBackgroundV3Spec.DEFAULT_SPEED;
    this.artworkCoordinator.setSpeed(this.speed);
  }

  @Builder
  private NativeBackground() {
    XComponent({
      id: 'wplayer_dynamic_background_v3',
      type: XComponentType.TEXTURE,
      libraryname: 'wplayerbackground'
    })
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onLoad((context: object): void => {
        const density = this.getUIContext().vp2px(1);
        this.artworkCoordinator.attachNativeContext(
          context as DynamicBackgroundV3NativeContext,
          density,
          this.speed,
          this.animationPaused || !this.pageVisible
        );
      })
      .onDestroy((): void => this.artworkCoordinator.detachNativeContext())
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.opticaldisc'))
        .fontSize(54)
        .fontColor([$r('app.color.text_primary')])
      Text('请先播放一首带封面的歌曲')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('v3 使用 aadishv/html-music 参考参数与原生 GPU 管线')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
    }
    .padding(24)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private Controls() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.currentTrackTitle())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFFFF')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`html-music · Twist ${DynamicBackgroundV3Spec.TWIST_ANGLE_RADIANS.toFixed(2)} · ` +
            `Blur ${DynamicBackgroundV3Spec.BLUR_RADIUS}px × ${DynamicBackgroundV3Spec.BLUR_PASSES} · ` +
            `Saturation ${DynamicBackgroundV3Spec.SATURATION.toFixed(2)} · ` +
            `${DynamicBackgroundV3Spec.FRAME_RATE} fps`)
            .fontSize(11)
            .fontColor('#B8FFFFFF')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button(this.animationPaused ? '继续' : '暂停')
          .fontSize(12)
          .fontColor('#FFFFFFFF')
          .backgroundColor('#33FFFFFF')
          .onClick((): void => this.toggleAnimation())
        Button('重置')
          .fontSize(12)
          .fontColor('#FFFFFFFF')
          .backgroundColor('#33FFFFFF')
          .onClick((): void => this.resetParameters())
      }
      .width('100%')

      DynamicBackgroundV3Slider({
        title: '动画速度',
        valueText: `${this.speed.toFixed(2)}×`,
        value: this.speed,
        minimum: 0.1,
        maximum: 2.5,
        step: 0.05,
        onChange: (value: number): void => {
          this.speed = value;
          this.artworkCoordinator.setSpeed(value);
        }
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: DynamicBackgroundV3Spec.CONTROL_PANEL_MAX_WIDTH })
    .padding(16)
    .borderRadius(24)
    .backgroundColor('#B31A1A1A')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.NativeBackground()

      if (!this.artworkCoordinator.hasBackgroundSource()) {
        this.EmptyState()
      }

      if (this.controlsVisible) {
        Column() {
          this.Controls()
        }
        .width('100%')
        .height('100%')
        .padding({
          left: DynamicBackgroundV3Spec.CONTROL_PANEL_MARGIN,
          right: DynamicBackgroundV3Spec.CONTROL_PANEL_MARGIN,
          bottom: this.bottomInset + DynamicBackgroundV3Spec.CONTROL_PANEL_MARGIN
        })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }

      Button() {
        SymbolGlyph(this.controlsVisible ?
          $r('sys.symbol.chevron_down') : $r('sys.symbol.gearshape_fill'))
          .fontSize(18)
          .fontColor(['#FFFFFFFF'])
      }
      .width(42)
      .height(42)
      .borderRadius(21)
      .backgroundColor('#80000000')
      .position({ right: 18, top: 18 })
      .accessibilityText(this.controlsVisible ? '隐藏参数' : '显示参数')
      .onClick((): void => {
        this.controlsVisible = !this.controlsVisible;
      })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor($r('app.color.page_background'))
  }
}
