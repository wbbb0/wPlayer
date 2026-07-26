import { image } from '@kit.ImageKit';
import displaySync from '@ohos.graphics.displaySync';
import { DynamicColor, ForegroundEmphasis } from '../../appearance/DynamicColor';
import { DynamicBackgroundV2Renderer } from '../../components/player/DynamicBackgroundV2Renderer';
import { DynamicBackgroundV2Spec } from '../../components/player/DynamicBackgroundV2Spec';
import { BundledArtworkCatalog } from '../../library/artwork/BundledArtworkCatalog';
import { PlayerStore } from '../../playback/model/PlaybackModels';

@Component
struct DynamicBackgroundV2Slider {
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
export struct DynamicBackgroundV2DebugPage {
  @ObjectLink playerStore: PlayerStore;
  @Prop bottomInset: number = 0;
  @State private speed: number = DynamicBackgroundV2Spec.DEFAULT_SPEED;
  @State private controlsVisible: boolean = true;
  @State private animationPaused: boolean = false;
  private readonly renderer: DynamicBackgroundV2Renderer = new DynamicBackgroundV2Renderer();
  private decodedArtwork?: image.PixelMap;
  private decodedArtworkUri: string = '';
  private loadingArtworkUri: string = '';
  private artworkLoadGeneration: number = 0;
  private pageVisible: boolean = false;
  private displaySync?: displaySync.DisplaySync;
  private animationStartedAt: number = 0;
  private pausedSeconds: number = 0;
  private readonly frameCallback: (info: displaySync.IntervalInfo) => void =
    (_info: displaySync.IntervalInfo): void => {
      this.ensureArtworkSource();
      const elapsedSeconds = this.animationPaused ? this.pausedSeconds :
        this.pausedSeconds + (Date.now() - this.animationStartedAt) / 1000;
      this.renderer.update(this.backgroundSource(), elapsedSeconds, this.speed);
    };

  aboutToAppear(): void {
    this.pageVisible = true;
    this.animationStartedAt = Date.now();
    this.displaySync = displaySync.create();
    this.displaySync.setExpectedFrameRateRange({
      min: DynamicBackgroundV2Spec.FRAME_RATE,
      max: DynamicBackgroundV2Spec.FRAME_RATE,
      expected: DynamicBackgroundV2Spec.FRAME_RATE
    });
    this.displaySync.on('frame', this.frameCallback);
    this.displaySync.start();
    this.ensureArtworkSource();
    this.renderer.update(this.backgroundSource(), this.pausedSeconds, this.speed);
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.artworkLoadGeneration += 1;
    this.loadingArtworkUri = '';
    this.displaySync?.stop();
    this.displaySync?.off('frame', this.frameCallback);
    this.displaySync = undefined;
    this.renderer.update(undefined, 0, this.speed);
    this.releaseDecodedArtwork();
  }

  private backgroundSource(): image.PixelMap | undefined {
    return this.playerStore.heroArtwork ?? this.decodedArtwork;
  }

  private releasePixelMap(pixelMap: image.PixelMap | undefined): void {
    pixelMap?.release().catch((error: Object): void => {
      const message = error instanceof Error ? error.message : `${error}`;
      console.warn(`Unable to release dynamic background v2 artwork: ${message}`);
    });
  }

  private releaseDecodedArtwork(): void {
    this.releasePixelMap(this.decodedArtwork);
    this.decodedArtwork = undefined;
    this.decodedArtworkUri = '';
  }

  private ensureArtworkSource(): void {
    if (!this.pageVisible) {
      return;
    }
    if (this.playerStore.heroArtwork !== undefined) {
      if (this.decodedArtwork !== undefined) {
        this.releaseDecodedArtwork();
      }
      return;
    }
    const uri = this.playerStore.heroArtworkUri;
    if (uri.length === 0 || BundledArtworkCatalog.isPath(uri) ||
      this.decodedArtworkUri === uri || this.loadingArtworkUri === uri) {
      return;
    }
    const generation = ++this.artworkLoadGeneration;
    this.loadingArtworkUri = uri;
    this.decodeArtworkUri(uri, generation);
  }

  private async decodeArtworkUri(uri: string, generation: number): Promise<void> {
    const source = image.createImageSource(uri);
    let pixelMap: image.PixelMap | undefined;
    try {
      pixelMap = await source.createPixelMapUsingAllocator({}, image.AllocatorType.SHARE_MEMORY);
      if (!this.pageVisible || generation !== this.artworkLoadGeneration ||
        uri !== this.playerStore.heroArtworkUri) {
        this.releasePixelMap(pixelMap);
        return;
      }
      this.releaseDecodedArtwork();
      this.decodedArtwork = pixelMap;
      this.decodedArtworkUri = uri;
      this.loadingArtworkUri = '';
      this.renderer.update(this.decodedArtwork, this.pausedSeconds, this.speed);
    } catch (error) {
      if (generation === this.artworkLoadGeneration) {
        this.loadingArtworkUri = '';
      }
      const message = error instanceof Error ? error.message : `${error}`;
      console.error(`Unable to decode dynamic background v2 artwork: ${message}`);
    } finally {
      await source.release();
    }
  }

  private hasBackgroundSource(): boolean {
    return this.backgroundSource() !== undefined ||
      (this.playerStore.heroArtworkUri.length > 0 &&
        !BundledArtworkCatalog.isPath(this.playerStore.heroArtworkUri));
  }

  private currentTrackTitle(): string {
    return this.playerStore.currentTrack?.title ?? '没有正在播放的歌曲';
  }

  private toggleAnimation(): void {
    if (this.animationPaused) {
      this.animationStartedAt = Date.now();
      this.animationPaused = false;
      return;
    }
    this.pausedSeconds += (Date.now() - this.animationStartedAt) / 1000;
    this.animationPaused = true;
  }

  private resetParameters(): void {
    this.speed = DynamicBackgroundV2Spec.DEFAULT_SPEED;
  }

  @Builder
  private ReferenceArtworkBackground() {
    Blank()
      .width('100%')
      .height('100%')
      .drawModifier(this.renderer)
      .renderGroup(true)
      .blur(DynamicBackgroundV2Spec.BLUR_RADIUS)
      .saturate(DynamicBackgroundV2Spec.SATURATION)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.opticaldisc'))
        .fontSize(54)
        .fontColor(['#FFFFFFFF'])
      Text('请先播放一首带封面的歌曲')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFFFF')
      Text('v2 直接使用原始封面复现参考网页')
        .fontSize(13)
        .fontColor(DynamicColor.withEmphasis('#FFFFFFFF', ForegroundEmphasis.MEDIUM))
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
          Text('参考网页原始参数 · Twist -3.25 · Blur 100 · Saturation 2.75 · 15 fps')
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

      DynamicBackgroundV2Slider({
        title: '动画速度',
        valueText: `${this.speed.toFixed(2)}×`,
        value: this.speed,
        minimum: 0.1,
        maximum: 2.5,
        step: 0.05,
        onChange: (value: number): void => {
          this.speed = value;
        }
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: DynamicBackgroundV2Spec.CONTROL_PANEL_MAX_WIDTH })
    .padding(16)
    .borderRadius(24)
    .backgroundColor('#B31A1A1A')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor('#FF000000')
        .hitTestBehavior(HitTestMode.None)

      if (this.hasBackgroundSource()) {
        this.ReferenceArtworkBackground()
      } else {
        this.EmptyState()
      }

      if (this.controlsVisible) {
        Column() {
          this.Controls()
        }
        .width('100%')
        .height('100%')
        .padding({
          left: DynamicBackgroundV2Spec.CONTROL_PANEL_MARGIN,
          right: DynamicBackgroundV2Spec.CONTROL_PANEL_MARGIN,
          bottom: this.bottomInset + DynamicBackgroundV2Spec.CONTROL_PANEL_MARGIN
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
    .backgroundColor('#FF000000')
  }
}
