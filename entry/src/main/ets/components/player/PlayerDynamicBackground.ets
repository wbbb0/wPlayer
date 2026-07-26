import { image } from '@kit.ImageKit';
import { DynamicBackgroundV3NativeContext } from 'libwplayerbackground.so';
import { DynamicColor } from '../../appearance/DynamicColor';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { DynamicBackgroundArtworkLoad } from './DynamicBackgroundArtworkLoad';
import { DynamicBackgroundV3Spec } from './DynamicBackgroundV3Spec';
import { PlayerDynamicBackgroundBinding } from './MiniPlayerBinding';
import { PlayerMorphController } from './PlayerMorphController';
import { PlayerLayoutSpec, PlayerMotionSpec } from './PlayerMotion';

@Component
struct PlayerDynamicBackgroundSurface {
  @ObjectLink @Watch('onPlayerStoreChanged') playerStore: PlayerStore;
  @ObjectLink @Watch('onBindingChanged') binding: PlayerDynamicBackgroundBinding;
  private nativeContext?: DynamicBackgroundV3NativeContext;
  private decodedArtwork?: image.PixelMap;
  private decodedArtworkUri: string = '';
  private readonly artworkLoad: DynamicBackgroundArtworkLoad =
    new DynamicBackgroundArtworkLoad();
  private uploadedArtworkKey: string = '';
  private uploadInProgressKey: string = '';
  private uploadRefreshPending: boolean = false;
  private uploadGeneration: number = 0;
  private mounted: boolean = false;
  private nativeContextGeneration: number = 0;
  private artworkSyncScheduled: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.ensureArtworkSource();
    this.ensureArtworkUploaded();
  }

  aboutToDisappear(): void {
    this.mounted = false;
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

  private onBindingChanged(): void {
    this.nativeContext?.setPaused(!this.binding.active);
    if (this.binding.active) {
      this.ensureArtworkUploaded();
    }
  }

  private onPlayerStoreChanged(): void {
    if (this.artworkSyncScheduled) {
      return;
    }
    this.artworkSyncScheduled = true;
    Promise.resolve().then((): void => {
      this.artworkSyncScheduled = false;
      if (!this.mounted) {
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
    const identity = track.smallArtworkHash.length > 0 ? track.smallArtworkHash :
      (track.largeArtworkHash.length > 0 ? track.largeArtworkHash : this.currentArtworkUri());
    if (this.playerStore.miniArtwork !== undefined) {
      return `artwork:${identity.length > 0 ? identity : track.id}:mini:` +
        `${this.playerStore.miniArtworkRevision}`;
    }
    if (this.decodedArtworkUri === this.currentArtworkUri() &&
      this.decodedArtwork !== undefined) {
      return `artwork:${identity.length > 0 ? identity : track.id}:decoded:` +
        this.decodedArtworkUri;
    }
    return `artwork:${identity.length > 0 ? identity : track.id}:hero:` +
      `${this.playerStore.heroArtworkRevision}`;
  }

  private releasePixelMap(pixelMap: image.PixelMap | undefined): void {
    pixelMap?.release().catch((error: Object): void => {
      const message = error instanceof Error ? error.message : `${error}`;
      console.warn(`Unable to release player dynamic background artwork: ${message}`);
    });
  }

  private releaseDecodedArtwork(): void {
    this.releasePixelMap(this.decodedArtwork);
    this.decodedArtwork = undefined;
    this.decodedArtworkUri = '';
  }

  private ensureArtworkSource(): void {
    if (!this.mounted) {
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
      if (this.decodedArtwork !== undefined) {
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
      if (!this.mounted || !this.artworkLoad.isCurrent(uri, generation) ||
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
      console.error(`Unable to decode player dynamic background artwork: ${message}`);
    } finally {
      if (source !== undefined) {
        try {
          await source.release();
        } catch (error) {
          const message = error instanceof Error ? error.message : `${error}`;
          console.warn(`Unable to release player dynamic background image source: ${message}`);
        }
      }
    }
  }

  private ensureArtworkUploaded(): void {
    const source = this.backgroundSource();
    const key = this.artworkKey();
    if (!this.mounted || this.nativeContext === undefined || source === undefined ||
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
      if (!this.mounted || key !== this.artworkKey() || this.nativeContext === undefined ||
        nativeContextGeneration !== this.nativeContextGeneration) {
        return;
      }
      this.nativeContext.setArtwork(pixels, info.size.width, info.size.height, true);
      this.uploadedArtworkKey = key;
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      console.error(`Unable to upload player dynamic background artwork: ${message}`);
    } finally {
      if (uploadGeneration === this.uploadGeneration) {
        const shouldRefresh = this.uploadRefreshPending;
        if (this.uploadInProgressKey === key) {
          this.uploadInProgressKey = '';
        }
        this.uploadRefreshPending = false;
        if (shouldRefresh && this.mounted) {
          this.ensureArtworkUploaded();
        }
      }
    }
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
    this.nativeContext?.setSpeed(DynamicBackgroundV3Spec.DEFAULT_SPEED);
    this.nativeContext?.setPaused(!this.binding.active);
  }

  build() {
    XComponent({
      id: 'wplayer_full_player_dynamic_background_v3',
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
}

@Component
export struct PlayerDynamicBackgroundLayer {
  @ObjectLink controller: PlayerMorphController;
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink binding: PlayerDynamicBackgroundBinding;
  @Prop collapsedSurfaceColor: string = '';
  @Prop playerThemeBackground: string = '';

  private canvasWidth(): number {
    const width = this.controller.fullPlayerFrame().width;
    return width > 0 ? width : this.controller.rootFrame.width;
  }

  private canvasHeight(): number {
    const height = this.controller.fullPlayerFrame().height;
    return height > 0 ? height : this.controller.rootFrame.height;
  }

  private edgeBleed(): number {
    return PlayerMotionSpec.morphBackgroundEdgeBleed(
      this.controller.playerExpandProgress
    );
  }

  private canvasScaleX(): number {
    return this.canvasWidth() > 0 ? 1 + this.edgeBleed() * 2 / this.canvasWidth() : 1;
  }

  private canvasScaleY(): number {
    return this.canvasHeight() > 0 ? 1 + this.edgeBleed() * 2 / this.canvasHeight() : 1;
  }

  build() {
    Stack() {
      Stack()
        .width(this.canvasWidth())
        .height(this.canvasHeight())
        .position({ x: this.edgeBleed(), y: this.edgeBleed() })
        .backgroundColor(DynamicColor.blendOpaque(
          this.collapsedSurfaceColor,
          this.playerThemeBackground,
          this.controller.clamp(this.controller.playerExpandProgress, 0, 1)
        ))
        .opacity(this.controller.playerMorphBackgroundOpacity)
        .scale({
          x: this.canvasScaleX(),
          y: this.canvasScaleY(),
          centerX: '50%',
          centerY: '50%'
        })

      Stack() {
        PlayerDynamicBackgroundSurface({
          playerStore: this.playerStore,
          binding: this.binding
        })
      }
      .width(this.canvasWidth())
      .height(this.canvasHeight())
      .position({ x: this.edgeBleed(), y: this.edgeBleed() })
      .opacity(PlayerMotionSpec.dynamicBackgroundReveal(
        this.controller.playerExpandProgress
      ))
      .scale({
        x: this.canvasScaleX(),
        y: this.canvasScaleY(),
        centerX: '50%',
        centerY: '50%'
      })
    }
    .width(this.controller.morphValue(
      this.controller.frozenMiniPlayerFrame.width,
      this.controller.fullPlayerFrame().width
    ) + this.edgeBleed() * 2)
    .height(this.controller.morphValue(
      this.controller.frozenMiniPlayerFrame.height,
      this.controller.fullPlayerFrame().height
    ) + this.edgeBleed() * 2)
    .position({ x: 0, y: 0 })
    .translate({
      x: this.controller.morphValue(
        this.controller.frozenMiniPlayerFrame.x,
        this.controller.fullPlayerFrame().x
      ) - this.edgeBleed(),
      y: this.controller.morphValue(
        this.controller.frozenMiniPlayerFrame.y,
        this.controller.fullPlayerFrame().y
      ) - this.edgeBleed()
    })
    .borderRadius(PlayerLayoutSpec.MORPH_SURFACE_RADIUS *
      (1 - this.controller.clamp(this.controller.playerExpandProgress, 0, 1)))
    .clip(true)
    .opacity(this.binding.active ? 1 : 0)
    // Keep the persistent native texture on-screen so its composition context
    // stays warm. While idle the whole background plane sits behind the app;
    // during a morph it moves above navigation but below player foreground.
    .zIndex(this.binding.active ? 1 : -1)
    .hitTestBehavior(HitTestMode.None)
  }
}
