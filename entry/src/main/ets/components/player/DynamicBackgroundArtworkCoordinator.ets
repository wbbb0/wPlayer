import { image } from '@kit.ImageKit';
import { DynamicBackgroundV3NativeContext } from 'libwplayerbackground.so';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { DynamicBackgroundArtworkLoad } from './DynamicBackgroundArtworkLoad';
import {
  DynamicBackgroundArtworkUploadState,
  DynamicBackgroundArtworkUploadTicket
} from './DynamicBackgroundArtworkUploadState';
import { DynamicBackgroundV3Spec } from './DynamicBackgroundV3Spec';

export class DynamicBackgroundNativeConfigurator {
  static apply(context: DynamicBackgroundV3NativeContext, density: number,
    speed: number, paused: boolean): void {
    context.setRenderScale(DynamicBackgroundV3Spec.nativeRenderScale(density));
    context.setFrameRates(
      DynamicBackgroundV3Spec.FRAME_RATE,
      DynamicBackgroundV3Spec.TRANSITION_FRAME_RATE,
      DynamicBackgroundV3Spec.ARTWORK_TRANSITION_DURATION_SECONDS,
      DynamicBackgroundV3Spec.INITIAL_REVEAL_DURATION_RATIO
    );
    context.setWorkTextureSize(DynamicBackgroundV3Spec.WORK_TEXTURE_SIZE);
    context.setBlurRadius(DynamicBackgroundV3Spec.BLUR_RADIUS);
    context.setOverscan(DynamicBackgroundV3Spec.OVERSCAN);
    context.setSpeed(speed);
    context.setPaused(paused);
  }
}

export class DynamicBackgroundArtworkCoordinator {
  private readonly logScope: string;
  private readonly artworkLoad: DynamicBackgroundArtworkLoad =
    new DynamicBackgroundArtworkLoad();
  private readonly uploadState: DynamicBackgroundArtworkUploadState =
    new DynamicBackgroundArtworkUploadState();
  private playerStore?: PlayerStore;
  private nativeContext?: DynamicBackgroundV3NativeContext;
  private decodedArtwork?: image.PixelMap;
  private decodedArtworkUri: string = '';
  private readonly inFlightUploadSources: Array<image.PixelMap> = [];
  private readonly retiredDecodedArtworks: Array<image.PixelMap> = [];
  private active: boolean = false;

  constructor(logScope: string) {
    this.logScope = logScope;
  }

  activate(playerStore: PlayerStore): void {
    this.playerStore = playerStore;
    this.active = true;
    this.sync();
  }

  deactivate(): void {
    this.active = false;
    this.artworkLoad.cancel();
    this.uploadState.cancel();
    this.nativeContext?.setPaused(true);
    this.releaseDecodedArtwork();
  }

  attachNativeContext(context: DynamicBackgroundV3NativeContext, density: number,
    speed: number, paused: boolean): void {
    this.uploadState.attachContext();
    this.nativeContext = context;
    DynamicBackgroundNativeConfigurator.apply(context, density, speed, paused);
    this.sync();
  }

  detachNativeContext(): void {
    this.uploadState.detachContext();
    this.nativeContext = undefined;
  }

  setPaused(paused: boolean): void {
    this.nativeContext?.setPaused(paused);
    if (!paused) {
      this.sync();
    }
  }

  setSpeed(speed: number): void {
    this.nativeContext?.setSpeed(speed);
  }

  sync(): void {
    this.ensureArtworkSource();
    this.ensureArtworkUploaded();
  }

  hasBackgroundSource(): boolean {
    return this.backgroundSource() !== undefined || this.currentArtworkUri().length > 0;
  }

  private currentArtworkUri(): string {
    const playerStore = this.playerStore;
    if (playerStore === undefined) {
      return '';
    }
    if (playerStore.miniArtworkUri.length > 0 &&
      !playerStore.miniArtworkUri.startsWith('demo-artwork://')) {
      return playerStore.miniArtworkUri;
    }
    return playerStore.heroArtworkUri;
  }

  private backgroundSource(): image.PixelMap | undefined {
    const playerStore = this.playerStore;
    if (playerStore === undefined) {
      return undefined;
    }
    if (playerStore.miniArtwork !== undefined) {
      return playerStore.miniArtwork;
    }
    const uri = this.currentArtworkUri();
    if (this.decodedArtworkUri === uri && this.decodedArtwork !== undefined) {
      return this.decodedArtwork;
    }
    if (uri.length > 0 && !uri.startsWith('demo-artwork://')) {
      return undefined;
    }
    return playerStore.heroArtwork;
  }

  private artworkKey(): string {
    const playerStore = this.playerStore;
    const track = playerStore?.currentTrack;
    if (playerStore === undefined || track === undefined ||
      this.backgroundSource() === undefined) {
      return '';
    }
    const identity = track.smallArtworkHash.length > 0 ? track.smallArtworkHash :
      (track.largeArtworkHash.length > 0 ? track.largeArtworkHash : this.currentArtworkUri());
    const prefix = `artwork:${identity.length > 0 ? identity : track.id}`;
    if (playerStore.miniArtwork !== undefined) {
      return `${prefix}:mini:${playerStore.miniArtworkRevision}`;
    }
    if (this.decodedArtworkUri === this.currentArtworkUri() &&
      this.decodedArtwork !== undefined) {
      return `${prefix}:decoded:${this.decodedArtworkUri}`;
    }
    return `${prefix}:hero:${playerStore.heroArtworkRevision}`;
  }

  private releasePixelMap(pixelMap: image.PixelMap | undefined): void {
    pixelMap?.release().catch((error: Object): void => {
      this.warn('Unable to release dynamic background artwork', error);
    });
  }

  private releaseDecodedArtwork(): void {
    const decodedArtwork = this.decodedArtwork;
    this.decodedArtwork = undefined;
    this.decodedArtworkUri = '';
    if (decodedArtwork === undefined) {
      return;
    }
    if (this.inFlightUploadSources.includes(decodedArtwork)) {
      this.retiredDecodedArtworks.push(decodedArtwork);
      return;
    }
    this.releasePixelMap(decodedArtwork);
  }

  private finishUsingUploadSource(source: image.PixelMap): void {
    const sourceIndex = this.inFlightUploadSources.indexOf(source);
    if (sourceIndex >= 0) {
      this.inFlightUploadSources.splice(sourceIndex, 1);
    }
    const retiredIndex = this.retiredDecodedArtworks.indexOf(source);
    if (retiredIndex >= 0 && !this.inFlightUploadSources.includes(source)) {
      this.retiredDecodedArtworks.splice(retiredIndex, 1);
      this.releasePixelMap(source);
    }
  }

  private ensureArtworkSource(): void {
    const playerStore = this.playerStore;
    if (!this.active || playerStore === undefined) {
      return;
    }
    if (playerStore.miniArtwork !== undefined) {
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
      if (!this.active || !this.artworkLoad.isCurrent(uri, generation) ||
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
      this.error('Unable to decode dynamic background artwork', error);
    } finally {
      if (source !== undefined) {
        try {
          await source.release();
        } catch (error) {
          this.warn('Unable to release dynamic background image source', error);
        }
      }
    }
  }

  private ensureArtworkUploaded(): void {
    const source = this.backgroundSource();
    const key = this.artworkKey();
    if (!this.active || this.nativeContext === undefined || source === undefined ||
      !this.uploadState.needsUpload(key)) {
      return;
    }
    if (this.uploadState.hasUploadInProgress()) {
      this.uploadState.noteDesiredKey(key);
      return;
    }
    const ticket = this.uploadState.begin(key);
    this.inFlightUploadSources.push(source);
    this.uploadArtwork(source, ticket);
  }

  private async uploadArtwork(source: image.PixelMap,
    ticket: DynamicBackgroundArtworkUploadTicket): Promise<void> {
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
      if (!this.uploadState.canCommit(
        ticket,
        this.artworkKey(),
        this.active,
        this.nativeContext !== undefined
      ) || this.nativeContext === undefined) {
        return;
      }
      this.nativeContext.setArtwork(pixels, info.size.width, info.size.height, true);
      this.uploadState.markUploaded(ticket);
    } catch (error) {
      this.error('Unable to upload dynamic background artwork', error);
    } finally {
      this.finishUsingUploadSource(source);
      const shouldRefresh = this.uploadState.finish(ticket);
      if (shouldRefresh && this.active) {
        this.ensureArtworkUploaded();
      }
    }
  }

  private warn(message: string, error: Object): void {
    const detail = error instanceof Error ? error.message : `${error}`;
    console.warn(`${this.logScope}: ${message}: ${detail}`);
  }

  private error(message: string, error: Object): void {
    const detail = error instanceof Error ? error.message : `${error}`;
    console.error(`${this.logScope}: ${message}: ${detail}`);
  }
}
