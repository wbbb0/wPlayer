import { image } from '@kit.ImageKit';
import displaySync from '@ohos.graphics.displaySync';
import { DynamicColor, ForegroundEmphasis } from '../../appearance/DynamicColor';
import { DynamicBackgroundDebugSpec } from '../../components/player/DynamicBackgroundDebugSpec';
import { DynamicBackgroundTextureAlgorithm } from '../../components/player/DynamicBackgroundTextureAlgorithm';
import { DynamicBackgroundTextureLayer } from '../../components/player/DynamicBackgroundTextureLayer';
import { DynamicBackgroundTextureProcessor } from '../../components/player/DynamicBackgroundTextureProcessor';
import { BundledArtworkCatalog } from '../../library/artwork/BundledArtworkCatalog';
import { PlayerStore } from '../../playback/model/PlaybackModels';

@Component
struct DynamicBackgroundSlider {
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
export struct DynamicBackgroundDebugPage {
  @ObjectLink playerStore: PlayerStore;
  @Prop bottomInset: number = 0;
  @State private elapsedSeconds: number = 0;
  @State private speed: number = DynamicBackgroundDebugSpec.DEFAULT_SPEED;
  @State private textureOpacity: number = DynamicBackgroundDebugSpec.DEFAULT_OPACITY;
  @State private travel: number = DynamicBackgroundDebugSpec.DEFAULT_TRAVEL;
  @State private rotation: number = DynamicBackgroundDebugSpec.DEFAULT_ROTATION;
  @State private textureScale: number = DynamicBackgroundDebugSpec.DEFAULT_TEXTURE_SCALE;
  @State private processedTextureRevision: number = 0;
  @State private processingDurationMs: number = 0;
  @State private processingInProgress: boolean = false;
  @State private controlsVisible: boolean = true;
  @State private animationPaused: boolean = false;
  private processedTexture?: image.PixelMap;
  private previousProcessedTexture?: image.PixelMap;
  private processedSourceRevision: number = -1;
  private processingSourceRevision: number = -1;
  private processingGeneration: number = 0;
  private pageVisible: boolean = false;
  private displaySync?: displaySync.DisplaySync;
  private animationStartedAt: number = 0;
  private pausedSeconds: number = 0;
  private readonly frameCallback: (info: displaySync.IntervalInfo) => void =
    (_info: displaySync.IntervalInfo): void => {
      this.ensureProcessedTexture();
      if (!this.animationPaused) {
        this.elapsedSeconds = this.pausedSeconds + (Date.now() - this.animationStartedAt) / 1000;
      }
    };

  aboutToAppear(): void {
    this.pageVisible = true;
    this.animationStartedAt = Date.now();
    this.displaySync = displaySync.create();
    this.displaySync.setExpectedFrameRateRange({
      min: DynamicBackgroundDebugSpec.FRAME_RATE,
      max: DynamicBackgroundDebugSpec.FRAME_RATE,
      expected: DynamicBackgroundDebugSpec.FRAME_RATE
    });
    this.displaySync.on('frame', this.frameCallback);
    this.displaySync.start();
    this.ensureProcessedTexture();
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.processingGeneration += 1;
    this.processingSourceRevision = -1;
    this.processingInProgress = false;
    this.displaySync?.stop();
    this.displaySync?.off('frame', this.frameCallback);
    this.displaySync = undefined;
    this.releaseProcessedTextures();
  }

  onDidBuild(): void {
    this.ensureProcessedTexture();
  }

  private contentColor(): string {
    return '#FFFFFFFF';
  }

  private processedBackgroundSource(_textureRevision: number): image.PixelMap | undefined {
    return this.processedTexture;
  }

  private processedPreviewSource(_textureRevision: number): image.PixelMap {
    return this.processedTexture as image.PixelMap;
  }

  private hasProcessedTexture(_textureRevision: number): boolean {
    return this.processedTexture !== undefined;
  }

  private releasePixelMap(pixelMap: image.PixelMap | undefined): void {
    pixelMap?.release().catch((error: Object): void => {
      const message = error instanceof Error ? error.message : `${error}`;
      console.warn(`Unable to release dynamic background texture: ${message}`);
    });
  }

  private releaseProcessedTextures(): void {
    this.releasePixelMap(this.previousProcessedTexture);
    this.releasePixelMap(this.processedTexture);
    this.previousProcessedTexture = undefined;
    this.processedTexture = undefined;
    this.processedSourceRevision = -1;
  }

  private replaceProcessedTexture(pixelMap: image.PixelMap, sourceRevision: number): void {
    this.releasePixelMap(this.previousProcessedTexture);
    this.previousProcessedTexture = this.processedTexture;
    this.processedTexture = pixelMap;
    this.processedSourceRevision = sourceRevision;
    this.processingSourceRevision = -1;
    this.processedTextureRevision += 1;
  }

  private processingDurationText(): string {
    if (this.processingInProgress) {
      return '处理中…';
    }
    return this.processingDurationMs > 0 ? `处理 ${this.processingDurationMs} ms` : '等待处理';
  }

  private ensureProcessedTexture(): void {
    if (!this.pageVisible) {
      return;
    }
    const sourceRevision = this.playerStore.heroArtworkRevision;
    if (this.processedSourceRevision === sourceRevision ||
      this.processingSourceRevision === sourceRevision) {
      return;
    }
    const source = this.playerStore.heroArtwork;
    if (source === undefined) {
      if (this.processingSourceRevision >= 0 || this.processingInProgress) {
        this.processingGeneration += 1;
      }
      this.processingSourceRevision = -1;
      this.processingInProgress = false;
      return;
    }
    const generation = ++this.processingGeneration;
    const processingStartedAt = Date.now();
    this.processingSourceRevision = sourceRevision;
    this.processingInProgress = true;
    DynamicBackgroundTextureProcessor.process(source)
      .then((pixelMap: image.PixelMap): void => {
        if (!this.pageVisible || generation !== this.processingGeneration ||
          sourceRevision !== this.playerStore.heroArtworkRevision) {
          this.releasePixelMap(pixelMap);
          return;
        }
        this.processingDurationMs = Math.max(1, Date.now() - processingStartedAt);
        this.processingInProgress = false;
        this.replaceProcessedTexture(pixelMap, sourceRevision);
      })
      .catch((error: Object): void => {
        if (generation === this.processingGeneration) {
          this.processingSourceRevision = -1;
          this.processingInProgress = false;
        }
        const message = error instanceof Error ? error.message : `${error}`;
        console.error(`Unable to preprocess dynamic background texture: ${message}`);
      });
  }

  private hasBackgroundSource(): boolean {
    return this.playerStore.heroArtwork !== undefined ||
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
    this.pausedSeconds = this.elapsedSeconds;
    this.animationPaused = true;
  }

  private resetParameters(): void {
    this.speed = DynamicBackgroundDebugSpec.DEFAULT_SPEED;
    this.textureOpacity = DynamicBackgroundDebugSpec.DEFAULT_OPACITY;
    this.travel = DynamicBackgroundDebugSpec.DEFAULT_TRAVEL;
    this.rotation = DynamicBackgroundDebugSpec.DEFAULT_ROTATION;
    this.textureScale = DynamicBackgroundDebugSpec.DEFAULT_TEXTURE_SCALE;
  }

  @Builder
  private TextureLayers() {
    ForEach([
      `${this.processedTextureRevision}:${this.textureScale.toFixed(2)}`
    ], (_textureKey: string) => {
      Stack() {
        Stack() {
          DynamicBackgroundTextureLayer({
            sourceProvider: (textureRevision: number): image.PixelMap | undefined =>
              this.processedBackgroundSource(textureRevision),
            sourceRevision: this.processedTextureRevision,
            textureScale: DynamicBackgroundDebugSpec.LAYER_ONE_TEXTURE_SCALE * this.textureScale,
            mirrorX: false
          })
        }
        .width('124%')
        .height('124%')
        .opacity(this.textureOpacity)
        .translate({
          x: DynamicBackgroundDebugSpec.layerOneX(this.elapsedSeconds, this.speed, this.travel),
          y: DynamicBackgroundDebugSpec.layerOneY(this.elapsedSeconds, this.speed, this.travel)
        })
        .rotate({
          angle: DynamicBackgroundDebugSpec.layerOneRotation(
            this.elapsedSeconds,
            this.speed,
            this.rotation
          )
        })
        .blendMode(BlendMode.SCREEN, BlendApplyType.FAST)
        .hitTestBehavior(HitTestMode.None)

        Stack() {
          DynamicBackgroundTextureLayer({
            sourceProvider: (textureRevision: number): image.PixelMap | undefined =>
              this.processedBackgroundSource(textureRevision),
            sourceRevision: this.processedTextureRevision,
            textureScale: DynamicBackgroundDebugSpec.LAYER_TWO_TEXTURE_SCALE * this.textureScale,
            mirrorX: true
          })
        }
        .width('124%')
        .height('124%')
        .opacity(this.textureOpacity * DynamicBackgroundDebugSpec.LAYER_TWO_OPACITY_RATIO)
        .translate({
          x: DynamicBackgroundDebugSpec.layerTwoX(this.elapsedSeconds, this.speed, this.travel),
          y: DynamicBackgroundDebugSpec.layerTwoY(this.elapsedSeconds, this.speed, this.travel)
        })
        .rotate({
          angle: DynamicBackgroundDebugSpec.layerTwoRotation(
            this.elapsedSeconds,
            this.speed,
            this.rotation
          )
        })
        .blendMode(BlendMode.PLUS, BlendApplyType.FAST)
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
    }, (textureKey: string): string => textureKey)
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.opticaldisc'))
        .fontSize(54)
        .fontColor([this.contentColor()])
      Text('请先播放一首带封面的歌曲')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.contentColor())
      Text('封面准备完成后重新进入此页面即可测试')
        .fontSize(13)
        .fontColor(DynamicColor.withEmphasis(this.contentColor(), ForegroundEmphasis.MEDIUM))
    }
    .padding(24)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ProcessedTexturePreview() {
    Column({ space: 6 }) {
      Text(`原始预处理纹理 · ${this.processingDurationText()}`)
        .fontSize(11)
        .fontColor('#FFFFFFFF')
      Image(this.processedPreviewSource(this.processedTextureRevision))
        .width(144)
        .height(144)
        .objectFit(ImageFit.Fill)
        .interpolation(ImageInterpolation.None)
        .draggable(false)
        .borderRadius(12)
    }
    .padding(8)
    .borderRadius(16)
    .backgroundColor('#B31A1A1A')
    .position({ left: 20, top: 100 })
    .hitTestBehavior(HitTestMode.None)
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
          Text(
            `扭曲 12% · 模糊 ${DynamicBackgroundTextureAlgorithm.BLUR_RADIUS} px · ` +
              `${this.processingDurationText()} · 30 fps`
          )
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

      DynamicBackgroundSlider({
        title: '速度',
        valueText: `${this.speed.toFixed(2)}×`,
        value: this.speed,
        minimum: 0.1,
        maximum: 3,
        step: 0.05,
        onChange: (value: number): void => {
          this.speed = value;
        }
      })
      DynamicBackgroundSlider({
        title: '纹理透明度',
        valueText: `${Math.round(this.textureOpacity * 100)}%`,
        value: this.textureOpacity,
        minimum: 0,
        maximum: 0.5,
        step: 0.01,
        onChange: (value: number): void => {
          this.textureOpacity = value;
        }
      })
      DynamicBackgroundSlider({
        title: '移动范围',
        valueText: `${Math.round(this.travel)} vp`,
        value: this.travel,
        minimum: 0,
        maximum: 64,
        step: 1,
        onChange: (value: number): void => {
          this.travel = value;
        }
      })
      DynamicBackgroundSlider({
        title: '旋转幅度',
        valueText: `${this.rotation.toFixed(2)}°`,
        value: this.rotation,
        minimum: 0,
        maximum: 30,
        step: 0.5,
        onChange: (value: number): void => {
          this.rotation = value;
        }
      })
      DynamicBackgroundSlider({
        title: '纹理缩放',
        valueText: `${Math.round(this.textureScale * 100)}%`,
        value: this.textureScale,
        minimum: 0.75,
        maximum: 5,
        step: 0.05,
        onChange: (value: number): void => {
          this.textureScale = value;
        }
      })
    }
    .width('100%')
    .constraintSize({ maxWidth: DynamicBackgroundDebugSpec.CONTROL_PANEL_MAX_WIDTH })
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

      if (this.hasProcessedTexture(this.processedTextureRevision)) {
        this.TextureLayers()
      } else if (!this.hasBackgroundSource()) {
        this.EmptyState()
      }

      Stack()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0], ['#08000000', 0.55], ['#24000000', 1]]
        })
        .hitTestBehavior(HitTestMode.None)

      if (this.controlsVisible && this.hasProcessedTexture(this.processedTextureRevision)) {
        this.ProcessedTexturePreview()
      }

      if (this.controlsVisible) {
        Column() {
          this.Controls()
        }
        .width('100%')
        .height('100%')
        .padding({
          left: DynamicBackgroundDebugSpec.CONTROL_PANEL_MARGIN,
          right: DynamicBackgroundDebugSpec.CONTROL_PANEL_MARGIN,
          bottom: this.bottomInset + DynamicBackgroundDebugSpec.CONTROL_PANEL_MARGIN
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
