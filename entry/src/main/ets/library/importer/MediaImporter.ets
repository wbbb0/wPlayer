import { common } from '@kit.AbilityKit';
import { ArtworkCache, ArtworkCacheResult } from '../artwork/ArtworkCache';
import {
  ArtworkImportInput,
  DuplicateCandidate,
  MusicRepository,
  TrackImportInput
} from '../data/MusicRepository';
import { MetadataReader } from '../metadata/MetadataReader';
import {
  calculateFullFingerprint,
  readArtworkBytesAsync
} from '../metadata/MediaFileTasks';
import { ImportConcurrencyPolicy } from './ImportConcurrencyPolicy';
import { ImportPerformanceTrace } from './ImportPerformanceTrace';
import { DuplicatePolicy } from './DuplicatePolicy';
import { ImportPreparationPolicy, PreparedItemState } from './ImportPreparationPolicy';
import {
  ArtworkPictureType,
  ImportProgress,
  ImportResult,
  ImportItemOutcome,
  ImportItemResult,
  MetadataReadResult,
  ParsedArtwork,
  ParsedMetadata
} from '../model/LibraryModels';
import {
  persistReadPermissions,
  revokeReadPermissions,
  selectAudioFiles
} from './MediaPickerService';

export type ImportProgressCallback = (progress: ImportProgress) => void;
export type ImportStartedCallback = () => void;
export type ImportItemCallback = (item: ImportItemResult) => void;

interface PreparedImport {
  uri: string;
  displayName: string;
  errorMessage: string;
  input?: TrackImportInput;
  failed: boolean;
  duplicate: boolean;
  duplicateTrackId?: number;
  duplicateSourceUri?: string;
}

interface CommitOutcome {
  imported: boolean;
  failed: boolean;
  trackId?: number;
  duplicateSource?: string;
  duplicateSourceUri?: string;
  errorMessage: string;
}

const IMPORT_BATCH_SIZE = 16;

export class MediaImporter {
  private readonly context: common.UIAbilityContext;
  private readonly repository: MusicRepository;
  private readonly artworkCache: ArtworkCache;
  private cancelRequested: boolean = false;
  private importing: boolean = false;
  private readonly artworkPreparations: Map<string, Promise<ArtworkCacheResult>> = new Map();

  constructor(context: common.UIAbilityContext, repository: MusicRepository, artworkCache: ArtworkCache) {
    this.context = context;
    this.repository = repository;
    this.artworkCache = artworkCache;
  }

  isImporting(): boolean {
    return this.importing;
  }

  cancel(): void {
    this.cancelRequested = true;
  }

  async selectAndImport(onProgress?: ImportProgressCallback,
    onStarted?: ImportStartedCallback, onItem?: ImportItemCallback): Promise<ImportResult> {
    if (this.importing) {
      throw new Error('An import is already running');
    }
    this.importing = true;
    this.cancelRequested = false;
    this.artworkPreparations.clear();
    let completedResult: ImportResult | undefined;
    let traceStarted = false;
    try {
      const uris = await selectAudioFiles(this.context);
      if (uris.length === 0) {
        return { imported: 0, duplicates: 0, failed: 0, items: [] };
      }
      onStarted?.();
      ImportPerformanceTrace.start(uris.length);
      traceStarted = true;
      completedResult = await this.importUris(uris, onProgress, onItem);
      return completedResult;
    } finally {
      const cleanupStartedAt = Date.now();
      try {
        await this.cleanupArtworkFiles();
      } catch (error) {
        console.warn(`Artwork orphan cleanup failed: ${MediaImporter.errorMessage(error)}`);
      }
      if (traceStarted) {
        ImportPerformanceTrace.mark('cleanup', cleanupStartedAt);
        ImportPerformanceTrace.finish(
          completedResult?.imported ?? 0,
          completedResult?.duplicates ?? 0,
          completedResult?.failed ?? 0
        );
      }
      this.importing = false;
      this.cancelRequested = false;
      this.artworkPreparations.clear();
    }
  }

  async clearLibrary(): Promise<void> {
    if (this.importing) {
      throw new Error('Cannot clear the library during an import');
    }
    await this.repository.clearLibrary();
    const assets = await this.repository.getUnreferencedArtworkAssets();
    for (let index = 0; index < assets.length; index += 1) {
      const asset = assets[index];
      if (asset.deleteSmall) {
        this.artworkCache.delete(asset.smallPath);
      }
      if (asset.deleteLarge) {
        this.artworkCache.delete(asset.largePath);
      }
      await this.repository.removeUnreferencedArtwork(asset.assetId);
    }
    this.artworkCache.cleanupTempFiles();
    await this.cleanupArtworkFiles();
  }

  cleanupArtworkStorage(): Promise<void> {
    return this.cleanupArtworkFiles();
  }

  private async importUris(uris: Array<string>, onProgress?: ImportProgressCallback,
    onItem?: ImportItemCallback): Promise<ImportResult> {
    const itemResults: Array<ImportItemResult> = [];
    const progress: ImportProgress = {
      total: uris.length,
      processed: 0,
      imported: 0,
      duplicates: 0,
      failed: 0,
      currentName: ''
    };
    this.notify(onProgress, progress);

    for (let batchOffset = 0; batchOffset < uris.length; batchOffset += IMPORT_BATCH_SIZE) {
      if (this.cancelRequested) {
        break;
      }
      const uriBatch = uris.slice(
        batchOffset, Math.min(batchOffset + IMPORT_BATCH_SIZE, uris.length)
      );
      progress.currentName = '正在检查重复文件';
      this.notify(onProgress, progress);

      const uriCheckStartedAt = Date.now();
      const existingUris = await this.repository.hasUris(uriBatch);
      ImportPerformanceTrace.mark('uri_check', uriCheckStartedAt, 0,
        `batch=${batchOffset / IMPORT_BATCH_SIZE + 1} count=${uriBatch.length}`);
      const pendingUris: Array<string> = [];
      for (let index = 0; index < uriBatch.length; index += 1) {
        const uri = uriBatch[index];
        if (existingUris.indexOf(uri) >= 0) {
          progress.duplicates += 1;
          progress.processed += 1;
          this.recordItem(itemResults, {
            uri: uri,
            displayName: uri,
            outcome: ImportItemOutcome.DUPLICATE,
            reason: '同一文件 URI 已在音乐库中',
            duplicateSourceUri: uri
          }, onItem);
        } else {
          pendingUris.push(uri);
        }
      }
      this.notify(onProgress, progress);

      if (pendingUris.length === 0) {
        continue;
      }
      const permissionStartedAt = Date.now();
      const permissionResult = await persistReadPermissions(pendingUris);
      ImportPerformanceTrace.mark('permission_persist', permissionStartedAt, 0,
        `count=${pendingUris.length} failed=${permissionResult.failedUris.length}`);
      progress.failed += permissionResult.failedUris.length;
      progress.processed += permissionResult.failedUris.length;
      permissionResult.failedUris.forEach((uri: string) => {
        this.recordItem(itemResults, {
          uri: uri,
          displayName: uri,
          outcome: ImportItemOutcome.FAILED,
          reason: '无法持久化文件读取授权'
        }, onItem);
      });
      this.notify(onProgress, progress);

      const preparedInputs: Array<TrackImportInput> = [];
      const revokeAfterBatch: Array<string> = [];
      progress.currentName = `正在并行读取音乐文件`;
      this.notify(onProgress, progress);
      const prepareStartedAt = Date.now();
      const prepared = await this.prepareImports(permissionResult.successfulUris);
      ImportPerformanceTrace.mark('prepare_batch', prepareStartedAt, 0,
        `count=${permissionResult.successfulUris.length}`);
      for (let index = 0; index < prepared.length; index += 1) {
        const item = prepared[index];
        const state = ImportPreparationPolicy.classify(
          item.failed, item.duplicate, item.input !== undefined
        );
        if (state === PreparedItemState.FAILED) {
          progress.failed += 1;
          progress.processed += 1;
          revokeAfterBatch.push(item.uri);
          this.recordItem(itemResults, {
            uri: item.uri,
            displayName: item.displayName,
            outcome: ImportItemOutcome.FAILED,
            reason: item.errorMessage.length > 0 ? item.errorMessage : '导入准备结果不完整'
          }, onItem);
        } else if (state === PreparedItemState.DUPLICATE) {
          progress.duplicates += 1;
          progress.processed += 1;
          revokeAfterBatch.push(item.uri);
          this.recordItem(itemResults, {
            uri: item.uri,
            displayName: item.displayName,
            outcome: ImportItemOutcome.DUPLICATE,
            reason: '完整文件内容与已有歌曲相同',
            duplicateTrackId: item.duplicateTrackId,
            duplicateSourceUri: item.duplicateSourceUri
          }, onItem);
        } else {
          preparedInputs.push(item.input as TrackImportInput);
        }
      }
      this.notify(onProgress, progress);

      if (this.cancelRequested) {
        await revokeReadPermissions(permissionResult.successfulUris);
        break;
      }
      if (preparedInputs.length > 0) {
        progress.currentName = '正在确认批次内重复文件';
        this.notify(onProgress, progress);
        const batchProofStartedAt = Date.now();
        await this.ensureBatchFingerprintProofs(preparedInputs);
        ImportPerformanceTrace.mark('batch_duplicate_proof', batchProofStartedAt, 0,
          `count=${preparedInputs.length}`);
        const uniqueInputs = this.removeBatchDuplicates(
          preparedInputs, itemResults, progress, revokeAfterBatch, onItem
        );
        progress.currentName = `正在生成 ${uniqueInputs.length} 首音乐的封面`;
        this.notify(onProgress, progress);
        const artworkBatchStartedAt = Date.now();
        await this.prepareArtworkInputs(uniqueInputs);
        ImportPerformanceTrace.mark('artwork_batch', artworkBatchStartedAt, 0,
          `count=${uniqueInputs.length}`);
        progress.currentName = `正在写入 ${uniqueInputs.length} 首音乐`;
        this.notify(onProgress, progress);
        const databaseStartedAt = Date.now();
        const results = await this.commitPreparedInputs(uniqueInputs);
        ImportPerformanceTrace.mark('database_commit', databaseStartedAt, 0,
          `count=${uniqueInputs.length}`);
        for (let index = 0; index < results.length; index += 1) {
          if (results[index].failed) {
            progress.failed += 1;
            this.recordItem(itemResults, {
              uri: uniqueInputs[index].uri,
              displayName: uniqueInputs[index].displayName,
              outcome: ImportItemOutcome.FAILED,
              reason: results[index].errorMessage
            }, onItem);
          } else if (results[index].imported) {
            progress.imported += 1;
            this.recordItem(itemResults, {
              uri: uniqueInputs[index].uri,
              displayName: uniqueInputs[index].displayName,
              outcome: ImportItemOutcome.IMPORTED,
              reason: '导入成功'
            }, onItem);
          } else {
            progress.duplicates += 1;
            revokeAfterBatch.push(uniqueInputs[index].uri);
            this.recordItem(itemResults, {
              uri: uniqueInputs[index].uri,
              displayName: uniqueInputs[index].displayName,
              outcome: ImportItemOutcome.DUPLICATE,
              reason: results[index].duplicateSource === 'content' ? '文件完整内容与已有歌曲相同' : '文件已存在',
              duplicateTrackId: results[index].trackId,
              duplicateSourceUri: results[index].duplicateSourceUri
            }, onItem);
          }
          if (results[index].failed) {
            revokeAfterBatch.push(uniqueInputs[index].uri);
          }
          progress.processed += 1;
        }
        this.notify(onProgress, progress);
      }
      const revokeStartedAt = Date.now();
      await revokeReadPermissions(revokeAfterBatch);
      ImportPerformanceTrace.mark('permission_revoke', revokeStartedAt, 0,
        `count=${revokeAfterBatch.length}`);
      this.artworkPreparations.clear();
    }
    progress.currentName = '';
    this.notify(onProgress, progress);
    return {
      imported: progress.imported,
      duplicates: progress.duplicates,
      failed: progress.failed,
      items: itemResults
    };
  }

  private async prepareImports(uris: Array<string>): Promise<Array<PreparedImport>> {
    const prepared: Array<PreparedImport | undefined> = new Array(uris.length);
    let nextIndex = 0;
    const consume = async (): Promise<void> => {
      while (!this.cancelRequested) {
        const index = nextIndex;
        nextIndex += 1;
        if (index >= uris.length) {
          return;
        }
        prepared[index] = await this.prepareImport(uris[index]);
      }
    };
    const workers: Array<Promise<void>> = [];
    const workerCount = Math.min(ImportConcurrencyPolicy.FILE_PROBE_CONCURRENCY, uris.length);
    for (let index = 0; index < workerCount; index += 1) {
      workers.push(consume());
    }
    await Promise.all(workers);
    return prepared.filter((item: PreparedImport | undefined): boolean => item !== undefined)
      .map((item: PreparedImport | undefined) => item as PreparedImport);
  }

  private async prepareImport(uri: string): Promise<PreparedImport> {
    const fileId = ImportPerformanceTrace.fileId(uri);
    const totalStartedAt = Date.now();
    try {
      const readResult = await MetadataReader.read(uri);
      const candidateStartedAt = Date.now();
      const candidates = await this.repository.findDuplicateCandidates(
        readResult.fileSize, readResult.quickFingerprint
      );
      ImportPerformanceTrace.mark('candidate_query', candidateStartedAt, fileId,
        `count=${candidates.length}`);
      if (ImportConcurrencyPolicy.needsFullFingerprint(candidates.length, 1)) {
        const fingerprintStartedAt = Date.now();
        readResult.fullFingerprint = await calculateFullFingerprint(uri);
        ImportPerformanceTrace.mark('foreground_hash', fingerprintStartedAt, fileId,
          MediaImporter.throughputDetails(readResult.fileSize, fingerprintStartedAt));
        await this.ensureCandidateFingerprints(candidates);
      }
      const duplicateCandidate = candidates.find((candidate: DuplicateCandidate) =>
        DuplicatePolicy.isConfirmedDuplicate(
          '', '',
          candidate.fullFingerprint, readResult.fullFingerprint
        ));
      if (duplicateCandidate !== undefined) {
        ImportPerformanceTrace.mark('file_prepare_total', totalStartedAt, fileId, 'duplicate=1');
        return {
          uri: uri,
          displayName: readResult.fileName,
          errorMessage: '',
          failed: false,
          duplicate: true,
          duplicateTrackId: duplicateCandidate.trackId,
          duplicateSourceUri: duplicateCandidate.uri
        };
      }
      const prepared: PreparedImport = {
        uri: uri,
        displayName: readResult.fileName,
        errorMessage: '',
        failed: false,
        duplicate: false,
        input: {
          uri: uri,
          displayName: readResult.fileName,
          fileSize: readResult.fileSize,
          modifiedAt: readResult.modifiedAt,
          quickFingerprint: readResult.quickFingerprint,
          fullFingerprint: readResult.fullFingerprint,
          authorizationPersisted: true,
          metadata: readResult.metadata,
          artworks: MediaImporter.artworkMetadataOnly(readResult.metadata.artworks)
        }
      };
      ImportPerformanceTrace.mark('file_prepare_total', totalStartedAt, fileId,
        `bytes=${readResult.fileSize} artworks=${readResult.metadata.artworks.length}`);
      return prepared;
    } catch (error) {
      const message = MediaImporter.errorMessage(error);
      console.warn(`Music import failed: ${message}`);
      ImportPerformanceTrace.mark('file_prepare_failed', totalStartedAt, fileId);
      return { uri: uri, displayName: uri, errorMessage: message, failed: true, duplicate: false };
    }
  }

  private async ensureCandidateFingerprints(candidates: Array<DuplicateCandidate>): Promise<void> {
    for (let index = 0; index < candidates.length; index += 1) {
      const candidate = candidates[index];
      if (candidate.fullFingerprint.length > 0) {
        continue;
      }
      const fileId = ImportPerformanceTrace.fileId(candidate.uri);
      const startedAt = Date.now();
      const fingerprint = await calculateFullFingerprint(candidate.uri);
      ImportPerformanceTrace.mark('candidate_hash', startedAt, fileId);
      await this.repository.updateFullFingerprint(candidate.trackId, fingerprint);
      candidate.fullFingerprint = fingerprint;
    }
  }

  private async ensureBatchFingerprintProofs(inputs: Array<TrackImportInput>): Promise<void> {
    const groups: Map<string, Array<TrackImportInput>> = new Map();
    for (let index = 0; index < inputs.length; index += 1) {
      const input = inputs[index];
      const key = `${input.fileSize}:${input.quickFingerprint}`;
      const group = groups.get(key) ?? [];
      group.push(input);
      groups.set(key, group);
    }
    const pending: Array<Promise<void>> = [];
    groups.forEach((group: Array<TrackImportInput>) => {
      if (!ImportConcurrencyPolicy.needsFullFingerprint(0, group.length)) {
        return;
      }
      group.forEach((input: TrackImportInput) => {
        if (input.fullFingerprint.length === 0) {
          const fileId = ImportPerformanceTrace.fileId(input.uri);
          const startedAt = Date.now();
          pending.push(calculateFullFingerprint(input.uri).then((fingerprint: string) => {
            input.fullFingerprint = fingerprint;
            ImportPerformanceTrace.mark('batch_hash', startedAt, fileId,
              MediaImporter.throughputDetails(input.fileSize, startedAt));
          }));
        }
      });
    });
    await Promise.all(pending);
  }

  private removeBatchDuplicates(inputs: Array<TrackImportInput>, itemResults: Array<ImportItemResult>,
    progress: ImportProgress, revokeAfterBatch: Array<string>,
    onItem?: ImportItemCallback): Array<TrackImportInput> {
    const unique: Array<TrackImportInput> = [];
    for (let index = 0; index < inputs.length; index += 1) {
      const input = inputs[index];
      const source = unique.find((existing: TrackImportInput) =>
        DuplicatePolicy.isConfirmedDuplicate(
          existing.quickFingerprint, input.quickFingerprint,
          existing.fullFingerprint, input.fullFingerprint
        ));
      if (source === undefined) {
        unique.push(input);
        continue;
      }
      progress.duplicates += 1;
      progress.processed += 1;
      revokeAfterBatch.push(input.uri);
      this.recordItem(itemResults, {
        uri: input.uri,
        displayName: input.displayName,
        outcome: ImportItemOutcome.DUPLICATE,
        reason: '本批次中存在完整内容相同的文件',
        duplicateSourceUri: source.uri
      }, onItem);
    }
    return unique;
  }

  private async prepareArtworkInputs(inputs: Array<TrackImportInput>): Promise<void> {
    let nextIndex = 0;
    const consume = async (): Promise<void> => {
      while (!this.cancelRequested) {
        const index = nextIndex++;
        if (index >= inputs.length) {
          return;
        }
        const input = inputs[index];
        const fileId = ImportPerformanceTrace.fileId(input.uri);
        const startedAt = Date.now();
        try {
          input.artworks = await this.prepareArtworks(input.uri, input.metadata);
        } catch (error) {
          console.warn(`Artwork preparation failed: ${MediaImporter.errorMessage(error)}`);
          input.artworks = MediaImporter.artworkMetadataOnly(input.metadata.artworks);
        }
        ImportPerformanceTrace.mark('artwork_total', startedAt, fileId,
          `count=${input.metadata.artworks.length}`);
      }
    };
    const workers: Array<Promise<void>> = [];
    const workerCount = Math.min(ImportConcurrencyPolicy.FILE_PROBE_CONCURRENCY, inputs.length);
    for (let index = 0; index < workerCount; index += 1) {
      workers.push(consume());
    }
    await Promise.all(workers);
  }

  private async commitPreparedInputs(inputs: Array<TrackImportInput>): Promise<Array<CommitOutcome>> {
    try {
      const batchResults = await this.repository.importTracks(inputs);
      const outcomes: Array<CommitOutcome> = [];
      for (let index = 0; index < batchResults.length; index += 1) {
        outcomes.push({
          imported: batchResults[index].imported,
          failed: false,
          trackId: batchResults[index].trackId,
          duplicateSource: batchResults[index].duplicateSource,
          errorMessage: ''
        });
      }
      return outcomes;
    } catch (error) {
      console.warn(`Batch import failed, retrying individually: ${MediaImporter.errorMessage(error)}`);
      const results: Array<CommitOutcome> = [];
      for (let index = 0; index < inputs.length; index += 1) {
        try {
          const result = await this.repository.importTrack(inputs[index]);
          results.push({
            imported: result.imported,
            failed: false,
            trackId: result.trackId,
            duplicateSource: result.duplicateSource,
            errorMessage: ''
          });
        } catch (itemError) {
          const message = MediaImporter.errorMessage(itemError);
          console.warn(`Music database write failed: ${message}`);
          results.push({ imported: false, failed: true, errorMessage: message });
        }
      }
      return results;
    }
  }

  private async prepareArtworks(uri: string, metadata: ParsedMetadata): Promise<Array<ArtworkImportInput>> {
    const parsedArtworks = metadata.artworks;
    const inputs: Array<ArtworkImportInput> = parsedArtworks.map((metadata: ParsedArtwork) => {
      const input: ArtworkImportInput = { metadata: metadata };
      return input;
    });
    const primaryIndex = MediaImporter.selectPrimaryArtwork(parsedArtworks);
    if (primaryIndex < 0) {
      return inputs;
    }
    const primaryArtwork = parsedArtworks[primaryIndex];
    const fileId = ImportPerformanceTrace.fileId(uri);
    const readStartedAt = Date.now();
    const sourceBuffer = await readArtworkBytesAsync(
      uri,
      primaryArtwork.byteOffset,
      primaryArtwork.byteLength,
      primaryArtwork.payloadOffset,
      primaryArtwork.unsynchronized
    );
    ImportPerformanceTrace.mark('artwork_read', readStartedAt, fileId,
      `bytes=${sourceBuffer.byteLength}`);
    const sourceBytes = new Uint8Array(sourceBuffer);
    const hashStartedAt = Date.now();
    const sourceHash = await ArtworkCache.hashSource(sourceBytes);
    ImportPerformanceTrace.mark('artwork_hash', hashStartedAt, fileId,
      `bytes=${sourceBytes.byteLength}`);
    const cached = await this.loadOrCacheArtwork(sourceHash, sourceBytes, fileId);
    inputs[primaryIndex] = {
      metadata: parsedArtworks[primaryIndex],
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
      primary: true
    };
    return inputs;
  }

  private async loadOrCacheArtwork(sourceHash: string, sourceBytes: Uint8Array,
    traceFileId: number): Promise<ArtworkCacheResult> {
    const activePreparation = this.artworkPreparations.get(sourceHash);
    if (activePreparation !== undefined) {
      return activePreparation;
    }
    const preparation = this.resolveArtwork(sourceHash, sourceBytes, traceFileId);
    this.artworkPreparations.set(sourceHash, preparation);
    return preparation;
  }

  private async resolveArtwork(sourceHash: string, sourceBytes: Uint8Array,
    traceFileId: number): Promise<ArtworkCacheResult> {
    const lookupStartedAt = Date.now();
    const existing = await this.repository.findArtworkBySourceHash(sourceHash);
    if (existing !== undefined && this.artworkCache.exists(existing.smallPath) &&
      this.artworkCache.exists(existing.largePath)) {
      ImportPerformanceTrace.mark('artwork_cache_lookup', lookupStartedAt, traceFileId, 'hit=1');
      return {
        sourceHash: sourceHash,
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
        }
      };
    }
    ImportPerformanceTrace.mark('artwork_cache_lookup', lookupStartedAt, traceFileId, 'hit=0');
    return this.artworkCache.cache(sourceBytes, sourceHash, traceFileId);
  }

  private async cleanupArtworkFiles(): Promise<void> {
    const referencedPaths = await this.repository.getReferencedArtworkPaths();
    this.artworkCache.cleanupTempFiles();
    this.artworkCache.cleanupOrphans(referencedPaths);
  }

  private static selectPrimaryArtwork(artworks: Array<ParsedArtwork>): number {
    let selectedIndex = -1;
    let selectedScore = Number.MAX_SAFE_INTEGER;
    let selectedArea = -1;
    for (let index = 0; index < artworks.length; index += 1) {
      const artwork = artworks[index];
      const score = MediaImporter.artworkScore(artwork.pictureType);
      if (score < 0) {
        continue;
      }
      const area = artwork.width * artwork.height;
      if (score < selectedScore || (score === selectedScore && area > selectedArea)) {
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

  private static artworkMetadataOnly(artworks: Array<ParsedArtwork>): Array<ArtworkImportInput> {
    return artworks.map((metadata: ParsedArtwork) => {
      const input: ArtworkImportInput = { metadata: metadata };
      return input;
    });
  }

  private notify(callback: ImportProgressCallback | undefined, progress: ImportProgress): void {
    if (callback === undefined) {
      return;
    }
    callback({
      total: progress.total,
      processed: progress.processed,
      imported: progress.imported,
      duplicates: progress.duplicates,
      failed: progress.failed,
      currentName: progress.currentName
    });
  }

  private recordItem(items: Array<ImportItemResult>, item: ImportItemResult,
    callback?: ImportItemCallback): void {
    items.push(item);
    callback?.(item);
  }

  private static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  private static throughputDetails(byteSize: number, startedAt: number): string {
    const elapsed = Math.max(1, Date.now() - startedAt);
    const megabytesPerSecond = Math.round(byteSize * 1000 / elapsed / 1024 / 1024);
    return `bytes=${byteSize} mbps=${megabytesPerSecond}`;
  }
}
