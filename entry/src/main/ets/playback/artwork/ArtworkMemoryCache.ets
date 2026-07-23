import { image } from '@kit.ImageKit';
import { ArtworkCache } from '../../library/artwork/ArtworkCache';
import { readArtworkBytesAsync } from '../../library/metadata/MediaFileTasks';
import { PlaybackTrack, QueueTrack } from '../model/PlaybackModels';
import { ResourceLeaseRegistry } from './ResourceLeaseRegistry';

const DEFAULT_MEMORY_BUDGET = 32 * 1024 * 1024;
const FULL_ARTWORK_MAX_EDGE = 2048;

interface CachedArtwork {
  pixelMap: image.PixelMap;
  byteSize: number;
  lastUsed: number;
}

export interface DecodedFullArtwork {
  pixelMap: image.PixelMap;
  byteSize: number;
}

enum ArtworkSizeVariant {
  SMALL = 0,
  LARGE = 1
}

export class ArtworkMemoryCache {
  private readonly context: Context;
  private readonly entries: Map<string, CachedArtwork> = new Map();
  private readonly loading: Map<string, Promise<image.PixelMap | undefined>> = new Map();
  private pinned: Set<string> = new Set();
  private totalBytes: number = 0;
  private fullArtworkBytes: number = 0;
  private readonly fullArtworkSizes: Map<image.PixelMap, number> = new Map();
  private readonly leases: ResourceLeaseRegistry<image.PixelMap>;
  private useSequence: number = 0;
  private readonly memoryBudget: number;
  private generation: number = 0;
  private closed: boolean = false;

  constructor(context: Context, memoryBudget: number = DEFAULT_MEMORY_BUDGET) {
    this.context = context;
    this.memoryBudget = memoryBudget;
    this.leases = new ResourceLeaseRegistry<image.PixelMap>((pixelMap: image.PixelMap) => {
      const fullSize = this.fullArtworkSizes.get(pixelMap) ?? 0;
      if (fullSize > 0) {
        this.fullArtworkSizes.delete(pixelMap);
        this.fullArtworkBytes = Math.max(0, this.fullArtworkBytes - fullSize);
      }
      pixelMap.release().catch((error: Object) => {
        console.warn(`Unable to release artwork PixelMap: ${ArtworkMemoryCache.messageOf(error)}`);
      });
    });
  }

  getLarge(track: QueueTrack): image.PixelMap | undefined {
    return this.getVariant(track, ArtworkSizeVariant.LARGE);
  }

  loadLarge(track: QueueTrack): Promise<image.PixelMap | undefined> {
    return this.loadVariant(track, ArtworkSizeVariant.LARGE);
  }

  pinCurrent(track: QueueTrack): void {
    this.pinned.clear();
    if (track.largeArtworkPath.length > 0) {
      this.pinned.add(ArtworkMemoryCache.keyOf(track, ArtworkSizeVariant.LARGE));
    }
  }

  private getVariant(track: QueueTrack, variant: ArtworkSizeVariant): image.PixelMap | undefined {
    const key = ArtworkMemoryCache.keyOf(track, variant);
    const entry = this.entries.get(key);
    if (entry !== undefined) {
      entry.lastUsed = ++this.useSequence;
      return entry.pixelMap;
    }
    return undefined;
  }

  private loadVariant(track: QueueTrack, variant: ArtworkSizeVariant): Promise<image.PixelMap | undefined> {
    if (this.closed) {
      return Promise.resolve(undefined);
    }
    const cached = this.getVariant(track, variant);
    if (cached !== undefined) {
      return Promise.resolve(cached);
    }
    const relativePath = ArtworkMemoryCache.pathOf(track, variant);
    if (relativePath.length === 0) {
      return Promise.resolve(undefined);
    }
    const key = ArtworkMemoryCache.keyOf(track, variant);
    const active = this.loading.get(key);
    if (active !== undefined) {
      return active;
    }
    const task = this.decodeThumbnail(relativePath, key, this.generation);
    this.loading.set(key, task);
    task.finally(() => {
      if (this.loading.get(key) === task) {
        this.loading.delete(key);
      }
    });
    return task;
  }

  async prefetchWindow(items: Array<QueueTrack>, currentIndex: number, radius: number): Promise<void> {
    if (currentIndex < 0 || currentIndex >= items.length) {
      return;
    }
    const nextPinned: Set<string> = new Set();
    for (let offset = -radius; offset <= radius; offset += 1) {
      const index = currentIndex + offset;
      if (index >= 0 && index < items.length) {
        if (index === currentIndex && items[index].largeArtworkPath.length > 0) {
          nextPinned.add(ArtworkMemoryCache.keyOf(items[index], ArtworkSizeVariant.LARGE));
        }
      }
    }
    this.pinned = nextPinned;
    await this.loadLarge(items[currentIndex]);
    for (let distance = 1; distance <= radius; distance += 1) {
      const previousIndex = currentIndex - distance;
      const nextIndex = currentIndex + distance;
      if (previousIndex >= 0) {
        await this.loadLarge(items[previousIndex]);
      }
      if (nextIndex < items.length) {
        await this.loadLarge(items[nextIndex]);
      }
    }
    this.evictIfNeeded();
  }

  async decodeFullArtwork(track: PlaybackTrack): Promise<DecodedFullArtwork | undefined> {
    if (track.artwork === undefined) {
      return undefined;
    }
    const buffer = await readArtworkBytesAsync(
      track.uri,
      track.artwork.byteOffset,
      track.artwork.byteLength,
      track.artwork.payloadOffset,
      track.format === 'mp3' && track.artwork.unsynchronized
    );
    if (buffer.byteLength === 0) {
      return undefined;
    }
    const source = image.createImageSource(buffer);
    let pixelMap: image.PixelMap | undefined;
    let ownershipTransferred = false;
    try {
      const info = await source.getImageInfo();
      const longest = Math.max(info.size.width, info.size.height);
      const scale = longest > FULL_ARTWORK_MAX_EDGE ? FULL_ARTWORK_MAX_EDGE / longest : 1;
      pixelMap = await source.createPixelMapUsingAllocator({
        desiredSize: {
          width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale))
        },
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      }, image.AllocatorType.SHARE_MEMORY);
      const pixelInfo = await pixelMap.getImageInfo();
      const byteSize = pixelInfo.size.width * pixelInfo.size.height * 4;
      this.fullArtworkSizes.set(pixelMap, byteSize);
      this.fullArtworkBytes += byteSize;
      ownershipTransferred = true;
      this.evictIfNeeded();
      return { pixelMap: pixelMap, byteSize: byteSize };
    } catch (error) {
      if (pixelMap !== undefined && !ownershipTransferred) {
        this.leases.requestRelease(pixelMap);
      }
      const cause = error as Error;
      throw cause;
    } finally {
      await source.release();
    }
  }

  releaseFullArtwork(artwork?: DecodedFullArtwork): void {
    if (artwork !== undefined) {
      this.leases.requestRelease(artwork.pixelMap);
    }
  }

  clear(): void {
    this.generation += 1;
    this.entries.forEach((entry: CachedArtwork) => this.leases.requestRelease(entry.pixelMap));
    this.entries.clear();
    this.loading.clear();
    this.pinned.clear();
    this.totalBytes = 0;
  }

  releaseAll(): void {
    this.closed = true;
    this.clear();
  }

  private async decodeThumbnail(relativePath: string, key: string,
    generation: number): Promise<image.PixelMap | undefined> {
    const path = ArtworkCache.resolveContextPath(this.context, relativePath);
    const source = image.createImageSource(path);
    let pixelMap: image.PixelMap | undefined;
    let ownershipTransferred = false;
    try {
      pixelMap = await source.createPixelMapUsingAllocator({}, image.AllocatorType.SHARE_MEMORY);
      if (this.closed || generation !== this.generation) {
        this.leases.requestRelease(pixelMap);
        ownershipTransferred = true;
        return undefined;
      }
      const info = await pixelMap.getImageInfo();
      if (this.closed || generation !== this.generation) {
        this.leases.requestRelease(pixelMap);
        ownershipTransferred = true;
        return undefined;
      }
      const byteSize = info.size.width * info.size.height * 4;
      this.entries.set(key, {
        pixelMap: pixelMap,
        byteSize: byteSize,
        lastUsed: ++this.useSequence
      });
      this.totalBytes += byteSize;
      ownershipTransferred = true;
      this.evictIfNeeded();
      return pixelMap;
    } catch (error) {
      if (pixelMap !== undefined && !ownershipTransferred) {
        this.leases.requestRelease(pixelMap);
      }
      console.warn(`Unable to decode cached artwork ${relativePath}: ${ArtworkMemoryCache.messageOf(error)}`);
      return undefined;
    } finally {
      await source.release();
    }
  }

  private evictIfNeeded(): void {
    while (this.totalBytes + this.fullArtworkBytes > this.memoryBudget) {
      let candidateKey = '';
      let oldestUse = Number.MAX_SAFE_INTEGER;
      this.entries.forEach((entry: CachedArtwork, key: string) => {
        if (!this.pinned.has(key) && entry.lastUsed < oldestUse) {
          candidateKey = key;
          oldestUse = entry.lastUsed;
        }
      });
      if (candidateKey.length === 0) {
        return;
      }
      const candidate = this.entries.get(candidateKey);
      if (candidate === undefined) {
        return;
      }
      this.entries.delete(candidateKey);
      this.totalBytes -= candidate.byteSize;
      this.leases.requestRelease(candidate.pixelMap);
    }
  }

  private static keyOf(track: QueueTrack, variant: ArtworkSizeVariant): string {
    const prefix = variant === ArtworkSizeVariant.SMALL ? 'small:' : 'large:';
    const hash = variant === ArtworkSizeVariant.SMALL ? track.smallArtworkHash : track.largeArtworkHash;
    const path = ArtworkMemoryCache.pathOf(track, variant);
    return `${prefix}${hash.length > 0 ? hash : path}`;
  }

  private static pathOf(track: QueueTrack, variant: ArtworkSizeVariant): string {
    return variant === ArtworkSizeVariant.SMALL ? track.smallArtworkPath : track.largeArtworkPath;
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
