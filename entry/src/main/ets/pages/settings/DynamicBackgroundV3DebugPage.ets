import { image } from '@kit.ImageKit';
import { DynamicBackgroundV3NativeContext } from 'libwplayerbackground.so';
import { DynamicBackgroundArtworkLoad } from '../../components/player/DynamicBackgroundArtworkLoad';
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
  private nativeContext?: DynamicBackgroundV3NativeContext;
  private decodedArtwork?: image.PixelMap;
  private decodedArtworkUri: string = '';
  private readonly artworkLoad: DynamicBackgroundArtworkLoad =
    new DynamicBackgroundArtworkLoad();
  private uploadedArtworkKey: string = '';
  private uploadInProgressKey: string = '';
  private uploadRefreshPending: boolean = false;
  private uploadGeneration: number = 0;
  private pageVisible: boolean = false;
  private nativeContextGeneration: number = 0;
  private artworkSyncScheduled: boolean = false;

  aboutToAppear(): void {
    this.pageVisible = true;
    this.nativeContext?.setPaused(this.animationPaused);
    this.ensureArtworkSource();
    this.ensureArtworkUploaded();
  }

  aboutToDisappear(): void {
    this.pageVisible = false;
    this.artworkLoad.cancel();
    this.uploadGeneration += 1;
    this.uploadInProgressKey = '';
    this.uploadRefreshPending = false;
    this.nativeContext?.setPaused(true);
    this.releaseDecodedArtwork();
  }

  onDidBuild(): void {
    this.ensureArtworkSource();
    this.ensureArtworkUploaded();
  }

  private onPlayerStoreChanged(): void {
    if (this.artworkSyncScheduled) {
      return;
    }
    this.artworkSyncScheduled = true;
    Promise.resolve().then((): void => {
      this.artworkSyncScheduled = false;
      if (!this.pageVisible) {
        return;
      }
      this.ensureArtworkSource();
      this.ensureArtworkUploaded();
    });
  }

  private currentArtworkUri(): string {
    if (this.playerStore.miniArtworkUri.length > 0 &&
      !this.playerStore.miniArtworkUri.startsWith('demo-artwork://')) {
      return this.playerStore.miniArtworkUri;
    }
    return this.playerStore.heroArtworkUri;
  }

  private backgroundSource(): image.PixelMap | undefined {
    if (this.playerStore.miniArtwork !== undefined) {
      return this.playerStore.miniArtwork;
    }
    const uri = this.currentArtworkUri();
    if (this.decodedArtworkUri === uri && this.decodedArtwork !== undefined) {
      return this.decodedArtwork;
    }
    // A URI-backed source is decoded to WORK_TEXTURE_SIZE below. Do not read the
    // full hero PixelMap while that small source is available.
    if (uri.length > 0 && !uri.startsWith('demo-artwork://')) {
      return undefined;
    }
    return this.playerStore.heroArtwork;
  }

  private artworkKey(): string {
    const track = this.playerStore.currentTrack;
    if (track === undefined || this.backgroundSource() === undefined) {
      return '';
    }
    const artworkIdentity = track.smallArtworkHash.length > 0 ?
      track.smallArtworkHash :
      (track.largeArtworkHash.length > 0 ? track.largeArtworkHash : this.currentArtworkUri());
    let sourceRevision = '';
    if (this.playerStore.miniArtwork !== undefined) {
      sourceRevision = `mini:${this.playerStore.miniArtworkRevision}`;
    } else if (this.decodedArtworkUri === this.currentArtworkUri() &&
      this.decodedArtwork !== undefined) {
      sourceRevision = `decoded:${this.decodedArtworkUri}`;
    } else if (this.playerStore.heroArtwork !== undefined) {
      sourceRevision = `hero:${this.playerStore.heroArtworkRevision}`;
    }
    return `artwork:${artworkIdentity.length > 0 ? artworkIdentity : track.id}:${sourceRevision}`;
  }

  private releasePixelMap(pixelMap: image.PixelMap | undefined): void {
    pixelMap?.release().catch((error: Object): void => {
      const message = error instanceof Error ? error.message : `${error}`;
      console.warn(`Unable to release dynamic background v3 artwork: ${message}`);
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
    if (this.playerStore.miniArtwork !== undefined) {
      this.artworkLoad.invalidateUnless();
      if (this.decodedArtwork !== undefined) {
        this.releaseDecodedArtwork();
      }
      return;
    }
    const uri = this.currentArtworkUri();
    if (uri.length === 0 || uri.startsWith('demo-artwork://')) {
      this.artworkLoad.invalidateUnless();
      if (this.playerStore.heroArtwork !== undefined &&
        this.decodedArtwork !== undefined) {
        this.releaseDecodedArtwork();
      }
      return;
    }
    this.artworkLoad.invalidateUnless(uri);
    if (this.decodedArtworkUri === uri || this.artworkLoad.isLoading(uri)) {
      return;
    }
    const generation = this.artworkLoad.begin(uri);
    this.decodeArtworkUri(uri, generation);
  }

  private async decodeArtworkUri(uri: string, generation: number): Promise<void> {
    let source: image.ImageSource | undefined;
    let pixelMap: image.PixelMap | undefined;
    try {
      source = image.createImageSource(uri);
      const sourceInfo = await source.getImageInfo();
      const longestEdge = Math.max(sourceInfo.size.width, sourceInfo.size.height);
      const maximumEdge = DynamicBackgroundV3Spec.WORK_TEXTURE_SIZE;
      const decodeScale = longestEdge > maximumEdge ? maximumEdge / longestEdge : 1;
      pixelMap = await source.createPixelMapUsingAllocator({
        desiredSize: {
          width: Math.max(1, Math.round(sourceInfo.size.width * decodeScale)),
          height: Math.max(1, Math.round(sourceInfo.size.height * decodeScale))
        },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      }, image.AllocatorType.SHARE_MEMORY);
      if (!this.pageVisible || !this.artworkLoad.isCurrent(uri, generation) ||
        uri !== this.currentArtworkUri()) {
        this.artworkLoad.finish(uri, generation);
        this.releasePixelMap(pixelMap);
        return;
      }
      this.releaseDecodedArtwork();
      this.decodedArtwork = pixelMap;
      this.decodedArtworkUri = uri;
      this.artworkLoad.finish(uri, generation);
      this.ensureArtworkUploaded();
    } catch (error) {
      this.artworkLoad.finish(uri, generation);
      const message = error instanceof Error ? error.message : `${error}`;
      console.error(`Unable to decode dynamic background v3 artwork: ${message}`);
    } finally {
      if (source !== undefined) {
        try {
          await source.release();
        } catch (error) {
          const message = error instanceof Error ? error.message : `${error}`;
          console.warn(`Unable to release dynamic background v3 image source: ${message}`);
        }
      }
    }
  }

  private ensureArtworkUploaded(): void {
    const source = this.backgroundSource();
    const key = this.artworkKey();
    if (!this.pageVisible || this.nativeContext === undefined || source === undefined ||
      key.length === 0 || key === this.uploadedArtworkKey) {
      return;
    }
    if (this.uploadInProgressKey.length > 0) {
      if (key !== this.uploadInProgressKey) {
        this.uploadRefreshPending = true;
      }
      return;
    }
    this.uploadRefreshPending = false;
    this.uploadInProgressKey = key;
    const uploadGeneration = ++this.uploadGeneration;
    this.uploadArtwork(source, key, this.nativeContextGeneration, uploadGeneration);
  }

  private async uploadArtwork(source: image.PixelMap, key: string,
    nativeContextGeneration: number, uploadGeneration: number): Promise<void> {
    try {
      const info = await source.getImageInfo();
      const stride = info.size.width * 4;
      const pixels = new ArrayBuffer(stride * info.size.height);
      await source.readPixels({
        pixels: pixels,
        offset: 0,
        stride: stride,
        region: { x: 0, y: 0, size: info.size }
      });
      if (!this.pageVisible || key !== this.artworkKey() || this.nativeContext === undefined ||
        nativeContextGeneration !== this.nativeContextGeneration) {
        return;
      }
      // PixelMap.readPixels(PositionArea) exposes BGRA byte order on HarmonyOS.
      this.nativeContext.setArtwork(pixels, info.size.width, info.size.height, true);
      this.uploadedArtworkKey = key;
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      console.error(`Unable to upload dynamic background v3 artwork: ${message}`);
    } finally {
      if (uploadGeneration === this.uploadGeneration) {
        const shouldRefresh = this.uploadRefreshPending;
        if (this.uploadInProgressKey === key) {
          this.uploadInProgressKey = '';
        }
        this.uploadRefreshPending = false;
        if (shouldRefresh && this.pageVisible) {
          this.ensureArtworkUploaded();
        }
      }
    }
  }

  private hasBackgroundSource(): boolean {
    return this.backgroundSource() !== undefined ||
      this.currentArtworkUri().length > 0;
  }

  private currentTrackTitle(): string {
    return this.playerStore.currentTrack?.title ?? '没有正在播放的歌曲';
  }

  private configureNativeContext(): void {
    const density = this.getUIContext().vp2px(1);
    this.nativeContext?.setRenderScale(DynamicBackgroundV3Spec.nativeRenderScale(density));
    this.nativeContext?.setFrameRates(
      DynamicBackgroundV3Spec.FRAME_RATE,
      DynamicBackgroundV3Spec.TRANSITION_FRAME_RATE,
      DynamicBackgroundV3Spec.ARTWORK_TRANSITION_DURATION_SECONDS,
      DynamicBackgroundV3Spec.INITIAL_REVEAL_DURATION_RATIO
    );
    this.nativeContext?.setWorkTextureSize(DynamicBackgroundV3Spec.WORK_TEXTURE_SIZE);
    this.nativeContext?.setBlurRadius(DynamicBackgroundV3Spec.BLUR_RADIUS);
    this.nativeContext?.setOverscan(DynamicBackgroundV3Spec.OVERSCAN);
    this.nativeContext?.setSpeed(this.speed);
    this.nativeContext?.setPaused(this.animationPaused || !this.pageVisible);
  }

  private toggleAnimation(): void {
    this.animationPaused = !this.animationPaused;
    this.nativeContext?.setPaused(this.animationPaused);
  }

  private resetParameters(): void {
    this.speed = DynamicBackgroundV3Spec.DEFAULT_SPEED;
    this.nativeContext?.setSpeed(this.speed);
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
        this.nativeContextGeneration += 1;
        this.nativeContext = context as DynamicBackgroundV3NativeContext;
        this.uploadedArtworkKey = '';
        this.configureNativeContext();
        this.ensureArtworkUploaded();
      })
      .onDestroy((): void => {
        this.nativeContextGeneration += 1;
        this.uploadGeneration += 1;
        this.nativeContext = undefined;
        this.uploadedArtworkKey = '';
        this.uploadInProgressKey = '';
        this.uploadRefreshPending = false;
      })
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
          this.nativeContext?.setSpeed(value);
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

      if (!this.hasBackgroundSource()) {
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
