import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { ArtworkCache } from '../../library/artwork/ArtworkCache';
import { BundledArtworkCatalog } from '../../library/artwork/BundledArtworkCatalog';
import { MusicRepository } from '../../library/data/MusicRepository';
import { MetadataReader } from '../../library/metadata/MetadataReader';
import { ArtworkMemoryCache, DecodedFullArtwork } from '../artwork/ArtworkMemoryCache';
import { PlaybackTrack, QueueTrack } from '../model/PlaybackModels';
import { RequestEpoch } from '../support/RequestEpoch';
import { ArtworkPrefetchCoordinator } from './ArtworkPrefetchCoordinator';

export interface PlaybackMediaHost {
  isTrackRequestCurrent(token: number): boolean;
  commitHeroArtwork(pixelMap: image.PixelMap): void;
  commitFullArtwork(artwork: DecodedFullArtwork): void;
  commitLyrics(track: PlaybackTrack, lyrics: string): void;
  clearLyricsAfterFailure(): void;
  commitRefreshedPalette(track: QueueTrack): void;
}

export class PlaybackMediaCoordinator {
  private static readonly PREFETCH_DELAY_MS: number = 1500;
  private context?: common.UIAbilityContext;
  private artworkCache?: ArtworkMemoryCache;
  private fullArtwork?: DecodedFullArtwork;
  private readonly requestEpoch: RequestEpoch = new RequestEpoch();
  private readonly prefetch: ArtworkPrefetchCoordinator =
    new ArtworkPrefetchCoordinator(PlaybackMediaCoordinator.PREFETCH_DELAY_MS);

  beginRequest(): number {
    this.invalidatePrefetch();
    return this.requestEpoch.begin();
  }

  invalidate(): number {
    this.invalidatePrefetch();
    return this.requestEpoch.invalidate();
  }

  currentRequest(): number {
    return this.requestEpoch.current();
  }

  isCurrent(token: number): boolean {
    return this.requestEpoch.isCurrent(token);
  }

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    this.artworkCache = new ArtworkMemoryCache(context);
  }

  reset(): void {
    this.requestEpoch.invalidate();
    this.invalidatePrefetch();
    this.artworkCache?.releaseAll();
    this.retireFullArtwork();
    this.context = undefined;
    this.artworkCache = undefined;
  }

  clearArtwork(): void {
    this.invalidatePrefetch();
    this.retireFullArtwork();
    this.artworkCache?.clear();
  }

  pinCurrent(track: QueueTrack): void {
    this.artworkCache?.pinCurrent(track);
  }

  cachedLarge(track: QueueTrack): image.PixelMap | undefined {
    return this.artworkCache?.getLarge(track);
  }

  hasFullArtwork(): boolean {
    return this.fullArtwork !== undefined;
  }

  resolveArtworkUri(relativePath: string): string {
    if (BundledArtworkCatalog.isPath(relativePath)) {
      return relativePath;
    }
    if (relativePath.length === 0 || this.context === undefined) {
      return '';
    }
    return `file://${ArtworkCache.resolveContextPath(this.context, relativePath)}`;
  }

  async loadHeroArtwork(track: QueueTrack, token: number, host: PlaybackMediaHost): Promise<void> {
    const pixelMap = await this.artworkCache?.loadLarge(track);
    if (host.isTrackRequestCurrent(token) && pixelMap !== undefined && this.fullArtwork === undefined) {
      host.commitHeroArtwork(pixelMap);
    }
  }

  async loadLyrics(track: PlaybackTrack, token: number, host: PlaybackMediaHost): Promise<void> {
    try {
      const lyrics = await MetadataReader.readLyrics(track.uri, track.fileSize, track.format);
      if (host.isTrackRequestCurrent(token)) {
        host.commitLyrics(track, lyrics);
      }
    } catch (error) {
      if (host.isTrackRequestCurrent(token)) {
        host.clearLyricsAfterFailure();
      }
      console.warn(`Unable to read embedded lyrics: ${PlaybackMediaCoordinator.messageOf(error)}`);
    }
  }

  async loadFullArtwork(track: PlaybackTrack, token: number, host: PlaybackMediaHost): Promise<void> {
    try {
      const cache = this.artworkCache;
      if (cache === undefined) {
        return;
      }
      const artwork = await cache.decodeFullArtwork(track);
      if (artwork === undefined) {
        return;
      }
      if (!host.isTrackRequestCurrent(token) || cache !== this.artworkCache) {
        cache.releaseFullArtwork(artwork);
        return;
      }
      this.fullArtwork = artwork;
      host.commitFullArtwork(artwork);
    } catch (error) {
      console.warn(`Unable to load full artwork: ${PlaybackMediaCoordinator.messageOf(error)}`);
    }
  }

  refreshPalette(repository: MusicRepository, trackId: number, token: number,
    host: PlaybackMediaHost): void {
    repository.repairTrackPaletteIfOutdated(trackId).then((updated: boolean): Promise<QueueTrack | undefined> => {
      if (!updated || !host.isTrackRequestCurrent(token)) {
        return Promise.resolve(undefined);
      }
      return repository.getPlaybackTrack(trackId);
    }).then((track: QueueTrack | undefined): void => {
      if (track !== undefined && host.isTrackRequestCurrent(token)) {
        host.commitRefreshedPalette(track);
      }
    }).catch((error: Object): void => {
      console.warn(`Unable to refresh artwork colors for track ${trackId}: ${PlaybackMediaCoordinator.messageOf(error)}`);
    });
  }

  schedulePrefetchWindow(items: Array<QueueTrack>, currentIndex: number, radius: number): void {
    const requestedItems = items.slice();
    this.prefetch.schedule(async (shouldContinue: () => boolean): Promise<void> => {
      const cache = this.artworkCache;
      if (!shouldContinue() || cache === undefined) {
        return;
      }
      try {
        await cache.prefetchWindow(
          requestedItems,
          currentIndex,
          radius,
          (): boolean => shouldContinue() && cache === this.artworkCache
        );
      } catch (error) {
        console.warn(`Unable to prefetch artwork window: ${PlaybackMediaCoordinator.messageOf(error)}`);
      }
    });
  }

  retireFullArtwork(): void {
    this.artworkCache?.releaseFullArtwork(this.fullArtwork);
    this.fullArtwork = undefined;
  }

  private invalidatePrefetch(): void {
    this.prefetch.invalidate();
  }

  static sameArtwork(previous: QueueTrack | undefined, next: QueueTrack, large: boolean): boolean {
    if (previous === undefined) {
      return false;
    }
    const previousHash = large ? previous.largeArtworkHash : previous.smallArtworkHash;
    const nextHash = large ? next.largeArtworkHash : next.smallArtworkHash;
    if (previousHash.length > 0 && nextHash.length > 0) {
      return previousHash === nextHash;
    }
    const previousPath = large ? previous.largeArtworkPath : previous.smallArtworkPath;
    const nextPath = large ? next.largeArtworkPath : next.smallArtworkPath;
    return previousPath.length > 0 && previousPath === nextPath;
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
