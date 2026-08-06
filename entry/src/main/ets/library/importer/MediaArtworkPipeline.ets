import { ArtworkCache, ArtworkCacheResult } from '../artwork/ArtworkCache';
import {
  ArtworkPalette,
  ARTWORK_PALETTE_VERSION
} from '../artwork/ArtworkPaletteExtractor';
import { ArtworkRepairPolicy } from '../artwork/ArtworkRepairPolicy';
import {
  ArtworkWorkCancellation,
  ArtworkWorkOutcome,
  ArtworkWorkRequest,
  ArtworkWorkResult,
  ArtworkWorkSession
} from '../artwork/ArtworkWorkSession';
import { MusicRepository } from '../data/MusicRepository';
import { ArtworkCleanupCandidate, ArtworkImportInput } from '../data/MusicRepository';
import { MetadataReader } from '../metadata/MetadataReader';
import {
  inspectMediaFiles,
  readArtworkBytesAsync
} from '../metadata/MediaFileTasks';
import {
  ArtworkPictureType,
  ParsedArtwork,
  ParsedMetadata
} from '../model/LibraryModels';
import { ImportConcurrencyPolicy } from './ImportConcurrencyPolicy';
import { ImportPerformanceTrace } from './ImportPerformanceTrace';
import { MediaImportOperation } from './MediaImportOperation';

export class MediaArtworkPipeline {
  private readonly repository: MusicRepository;
  private readonly artworkCache: ArtworkCache;
  private readonly preparations: Map<string, Promise<ArtworkCacheResult>> = new Map();
  private cleanupTail: Promise<void> = Promise.resolve();

  constructor(repository: MusicRepository, artworkCache: ArtworkCache) {
    this.repository = repository;
    this.artworkCache = artworkCache;
  }

  async waitForCleanup(): Promise<void> {
    await this.cleanupTail;
  }

  createSession(operation: MediaImportOperation): ArtworkWorkSession {
    const session = new ArtworkWorkSession(
      (request: ArtworkWorkRequest,
        cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> =>
        this.processItem(request, cancellation),
      false,
      ImportConcurrencyPolicy.ARTWORK_PROCESS_CONCURRENCY,
      operation
    );
    operation.attachQueue(session);
    return session;
  }

  clearOperationContext(): void {
    this.preparations.clear();
  }

  async processWorks(session: ArtworkWorkSession,
    works: Array<ArtworkWorkRequest>,
    onResult: (request: ArtworkWorkRequest, result: ArtworkWorkResult) => void): Promise<void> {
    let offset = 0;
    while (offset < works.length) {
      if (session.isCancelled()) {
        const skipped = MediaArtworkPipeline.result(ArtworkWorkOutcome.SKIPPED);
        for (let index = offset; index < works.length; index += 1) {
          onResult(works[index], skipped);
        }
        return;
      }
      const batch = works.slice(
        offset,
        Math.min(offset + ImportConcurrencyPolicy.ARTWORK_PROCESS_BATCH_SIZE, works.length)
      );
      const tasks = batch.map(
        (request: ArtworkWorkRequest): Promise<ArtworkWorkResult> =>
          session.enqueue(request)
      );
      const results = await Promise.all(tasks);
      for (let index = 0; index < batch.length; index += 1) {
        onResult(batch[index], results[index]);
      }
      offset += batch.length;
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 0);
      });
    }
  }

  async prepareArtworks(uri: string, metadata: ParsedMetadata,
    cancellation: ArtworkWorkCancellation): Promise<Array<ArtworkImportInput>> {
    const parsed = metadata.artworks;
    const inputs = parsed.map((artwork: ParsedArtwork): ArtworkImportInput => {
      return { metadata: artwork };
    });
    const primaryIndex = MediaArtworkPipeline.selectPrimaryArtwork(parsed);
    if (primaryIndex < 0) {
      return inputs;
    }
    const primary = parsed[primaryIndex];
    const fileId = ImportPerformanceTrace.fileId(uri);
    const readStartedAt = Date.now();
    const buffer = await readArtworkBytesAsync(
      uri, primary.byteOffset, primary.byteLength, primary.payloadOffset, primary.unsynchronized
    );
    ImportPerformanceTrace.mark(
      'artwork_read', readStartedAt, fileId, `bytes=${buffer.byteLength}`
    );
    MediaArtworkPipeline.throwIfCancelled(cancellation);
    const bytes = new Uint8Array(buffer);
    const hashStartedAt = Date.now();
    const sourceHash = await ArtworkCache.hashSource(bytes);
    ImportPerformanceTrace.mark(
      'artwork_hash', hashStartedAt, fileId, `bytes=${bytes.byteLength}`
    );
    MediaArtworkPipeline.throwIfCancelled(cancellation);
    const cached = await this.loadOrCache(
      sourceHash, bytes, fileId, cancellation
    );
    inputs[primaryIndex] = {
      metadata: primary,
      sourceHash: cached.sourceHash,
      smallHash: cached.small.hash,
      smallPath: cached.small.relativePath,
      smallFormat: cached.small.format,
      smallWidth: cached.small.width,
      smallHeight: cached.small.height,
      smallByteSize: cached.small.byteSize,
      largeHash: cached.large.hash,
      largePath: cached.large.relativePath,
      largeFormat: cached.large.format,
      largeWidth: cached.large.width,
      largeHeight: cached.large.height,
      largeByteSize: cached.large.byteSize,
      encodingVersion: cached.encodingVersion,
      palettePrimary: cached.palette.primary,
      paletteSecondary: cached.palette.secondary,
      paletteAccent: cached.palette.accent,
      primary: true
    };
    return inputs;
  }

  private async processItem(item: ArtworkWorkRequest,
    cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> {
    if (cancellation.isCancelled()) {
      return MediaArtworkPipeline.result(ArtworkWorkOutcome.SKIPPED);
    }
    let metadata = item.metadata;
    try {
      const startedAt = Date.now();
      if (metadata === undefined) {
        const readResult = await MetadataReader.read(item.uri);
        if (cancellation.isCancelled()) {
          return MediaArtworkPipeline.result(ArtworkWorkOutcome.SKIPPED);
        }
        if (readResult.fileSize !== item.fileSize || readResult.modifiedAt !== item.modifiedAt) {
          return MediaArtworkPipeline.result(ArtworkWorkOutcome.STALE);
        }
        metadata = readResult.metadata;
      }
      const accepted = await this.repository.markArtworkProcessing(
        item.trackId, item.fileSize, item.modifiedAt
      );
      if (!accepted) {
        return MediaArtworkPipeline.result(ArtworkWorkOutcome.STALE);
      }
      const artworks = await this.prepareArtworks(item.uri, metadata, cancellation);
      if (cancellation.isCancelled()) {
        await this.repository.deferArtwork(item.trackId, item.fileSize, item.modifiedAt);
        return MediaArtworkPipeline.result(ArtworkWorkOutcome.SKIPPED);
      }
      if (!await this.mediaSnapshotMatches(item)) {
        await this.repository.deferArtwork(item.trackId, item.fileSize, item.modifiedAt);
        return MediaArtworkPipeline.result(ArtworkWorkOutcome.STALE);
      }
      if (cancellation.isCancelled()) {
        await this.repository.deferArtwork(item.trackId, item.fileSize, item.modifiedAt);
        return MediaArtworkPipeline.result(ArtworkWorkOutcome.SKIPPED);
      }
      const completed = await this.repository.completeArtwork(
        item.trackId, item.fileSize, item.modifiedAt, artworks
      );
      ImportPerformanceTrace.mark(
        'artwork_total', startedAt, ImportPerformanceTrace.fileId(item.uri),
        `count=${metadata.artworks.length}`
      );
      return MediaArtworkPipeline.result(
        completed ? ArtworkWorkOutcome.COMPLETED : ArtworkWorkOutcome.STALE,
        metadata.artworks.length > 0
      );
    } catch (error) {
      const message = MediaArtworkPipeline.errorMessage(error);
      console.warn(`Artwork queue failed for track ${item.trackId}: ${message}`);
      if (cancellation.isCancelled()) {
        await this.repository.deferArtwork(item.trackId, item.fileSize, item.modifiedAt);
        return MediaArtworkPipeline.result(ArtworkWorkOutcome.SKIPPED);
      }
      await this.repository.failArtwork(item.trackId, item.fileSize, item.modifiedAt, message);
      return MediaArtworkPipeline.result(
        ArtworkWorkOutcome.FAILED,
        metadata !== undefined && metadata.artworks.length > 0,
        message
      );
    }
  }

  private async loadOrCache(sourceHash: string, sourceBytes: Uint8Array,
    traceFileId: number, cancellation: ArtworkWorkCancellation): Promise<ArtworkCacheResult> {
    const active = this.preparations.get(sourceHash);
    if (active !== undefined) {
      const cached = await active;
      MediaArtworkPipeline.throwIfCancelled(cancellation);
      return cached;
    }
    const preparation = this.resolveArtwork(
      sourceHash, sourceBytes, traceFileId, cancellation
    );
    this.preparations.set(sourceHash, preparation);
    try {
      return await preparation;
    } catch (error) {
      if (this.preparations.get(sourceHash) === preparation) {
        this.preparations.delete(sourceHash);
      }
      throw new Error(MediaArtworkPipeline.errorMessage(error));
    } finally {
      while (this.preparations.size > 128) {
        const oldest = this.preparations.keys().next();
        if (oldest.done) {
          break;
        }
        this.preparations.delete(oldest.value);
      }
    }
  }

  private async resolveArtwork(sourceHash: string, sourceBytes: Uint8Array,
    traceFileId: number, cancellation: ArtworkWorkCancellation): Promise<ArtworkCacheResult> {
    const lookupStartedAt = Date.now();
    const existing = await this.repository.findArtworkBySourceHash(sourceHash);
    MediaArtworkPipeline.throwIfCancelled(cancellation);
    const smallExists = existing !== undefined ?
      await this.artworkCache.existsAsync(existing.smallPath) : false;
    MediaArtworkPipeline.throwIfCancelled(cancellation);
    const largeExists = existing !== undefined && smallExists ?
      await this.artworkCache.existsAsync(existing.largePath) : false;
    MediaArtworkPipeline.throwIfCancelled(cancellation);
    if (existing !== undefined && smallExists && largeExists &&
      !ArtworkRepairPolicy.hasOutdatedEncoding(
        existing.encodingVersion, existing.smallFormat, existing.largeFormat
      ) &&
      !ArtworkRepairPolicy.hasSuspiciousLargeVariant(
        existing.smallWidth, existing.smallHeight, existing.smallByteSize,
        existing.largeWidth, existing.largeHeight, existing.largeByteSize
      ) &&
      !ArtworkRepairPolicy.hasOutdatedVariantDimensions(
        existing.sourceWidth, existing.sourceHeight,
        existing.smallWidth, existing.smallHeight,
        existing.largeWidth, existing.largeHeight
      )) {
      let palette: ArtworkPalette = {
        primary: existing.palettePrimary,
        secondary: existing.paletteSecondary,
        accent: existing.paletteAccent
      };
      if (existing.paletteVersion < ARTWORK_PALETTE_VERSION) {
        palette = await this.artworkCache.extractPalette(existing.smallPath);
        MediaArtworkPipeline.throwIfCancelled(cancellation);
        await this.repository.updateArtworkPalettes([{
          id: existing.assetId,
          palette: palette,
          expectedVersion: existing.paletteVersion
        }]);
      }
      ImportPerformanceTrace.mark(
        'artwork_cache_lookup', lookupStartedAt, traceFileId,
        existing.paletteVersion >= ARTWORK_PALETTE_VERSION ?
          'hit=1' : 'hit=1 palette_refreshed=1'
      );
      return {
        sourceHash: sourceHash,
        encodingVersion: existing.encodingVersion,
        small: {
          hash: existing.smallHash,
          relativePath: existing.smallPath,
          format: existing.smallFormat,
          width: existing.smallWidth,
          height: existing.smallHeight,
          byteSize: existing.smallByteSize
        },
        large: {
          hash: existing.largeHash,
          relativePath: existing.largePath,
          format: existing.largeFormat,
          width: existing.largeWidth,
          height: existing.largeHeight,
          byteSize: existing.largeByteSize
        },
        palette: palette
      };
    }
    ImportPerformanceTrace.mark(
      'artwork_cache_lookup', lookupStartedAt, traceFileId,
      existing === undefined ? 'hit=0' : 'hit=0 reason=suspicious'
    );
    return this.artworkCache.cache(
      sourceBytes, sourceHash, traceFileId,
      (): boolean => !cancellation.isCancelled()
    );
  }

  private async mediaSnapshotMatches(item: ArtworkWorkRequest): Promise<boolean> {
    const inspections = await inspectMediaFiles([{
      uri: item.uri,
      artworkSmallPath: '',
      artworkLargePath: ''
    }]);
    return inspections.length === 1 && inspections[0].available &&
      inspections[0].fileSize === item.fileSize &&
      inspections[0].modifiedAt === item.modifiedAt;
  }

  private static selectPrimaryArtwork(artworks: Array<ParsedArtwork>): number {
    let selectedIndex = -1;
    let selectedScore = Number.MAX_SAFE_INTEGER;
    let selectedArea = -1;
    for (let index = 0; index < artworks.length; index += 1) {
      const artwork = artworks[index];
      const score = MediaArtworkPipeline.artworkScore(artwork.pictureType);
      const area = artwork.width * artwork.height;
      if (score >= 0 && (
        score < selectedScore || (score === selectedScore && area > selectedArea)
      )) {
        selectedIndex = index;
        selectedScore = score;
        selectedArea = area;
      }
    }
    return selectedIndex;
  }

  private static artworkScore(type: ArtworkPictureType): number {
    if (type === ArtworkPictureType.FRONT_COVER) {
      return 0;
    }
    if (type === ArtworkPictureType.OTHER) {
      return 1;
    }
    if (type === ArtworkPictureType.MEDIA) {
      return 2;
    }
    if (type === ArtworkPictureType.LEAFLET) {
      return 3;
    }
    if (type === ArtworkPictureType.BACK_COVER) {
      return 4;
    }
    return -1;
  }

  private static throwIfCancelled(cancellation: ArtworkWorkCancellation): void {
    if (cancellation.isCancelled()) {
      throw new Error('Artwork operation cancelled');
    }
  }

  private static result(outcome: ArtworkWorkOutcome,
    sourceHasArtwork: boolean = false, errorMessage: string = ''): ArtworkWorkResult {
    return {
      outcome: outcome,
      sourceHasArtwork: sourceHasArtwork,
      errorMessage: errorMessage
    };
  }

  private static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  scheduleCleanup(shouldContinue: () => boolean = (): boolean => true): Promise<void> {
    const cleanup = this.cleanupTail.then(async (): Promise<void> => {
      if (!shouldContinue()) {
        return;
      }
      await this.cleanupUnreferencedAssets(shouldContinue);
      if (!shouldContinue()) {
        return;
      }
      await this.artworkCache.cleanupTempFiles(shouldContinue);
      if (!shouldContinue()) {
        return;
      }
      const referencedPaths = await this.repository.getReferencedArtworkPaths();
      if (!shouldContinue()) {
        return;
      }
      await this.artworkCache.cleanupOrphans(referencedPaths, shouldContinue);
      if (!shouldContinue()) {
        return;
      }
      await this.artworkCache.cleanupEmptyDirectories(shouldContinue);
    });
    this.cleanupTail = cleanup.catch((error: Object): void => {
      const message = error instanceof Error ? error.message : `${error}`;
      console.warn(`Artwork orphan cleanup failed: ${message}`);
    });
    return this.cleanupTail;
  }

  private async cleanupUnreferencedAssets(shouldContinue: () => boolean): Promise<void> {
    const assets = await this.repository.getUnreferencedArtworkAssets();
    for (let index = 0; index < assets.length && shouldContinue(); index += 1) {
      const asset = assets[index];
      try {
        await this.deleteUnreferencedAsset(asset);
      } catch (error) {
        const message = error instanceof Error ? error.message : `${error}`;
        console.warn(`Artwork asset cleanup skipped ${asset.assetId}: ${message}`);
      }
    }
  }

  private async deleteUnreferencedAsset(asset: ArtworkCleanupCandidate): Promise<void> {
    if (asset.deleteSmall) {
      await this.artworkCache.deleteAsync(asset.smallPath);
    }
    if (asset.deleteLarge && asset.largePath !== asset.smallPath) {
      await this.artworkCache.deleteAsync(asset.largePath);
    }
    await this.repository.removeUnreferencedArtwork(asset.assetId);
  }
}
