import { common } from '@kit.AbilityKit';
import { ArtworkCache } from '../artwork/ArtworkCache';
import {
  ArtworkWorkOutcome,
  ArtworkWorkRequest,
  ArtworkWorkResult,
  ArtworkWorkSession
} from '../artwork/ArtworkWorkSession';
import {
  ArtworkImportInput,
  DuplicateCandidate,
  MusicRepository,
  TrackImportInput
} from '../data/MusicRepository';
import { MetadataReader } from '../metadata/MetadataReader';
import { calculateFullFingerprint } from '../metadata/MediaFileTasks';
import { ImportConcurrencyPolicy } from './ImportConcurrencyPolicy';
import { MediaImportOperation } from './MediaImportOperation';
import { BatchDuplicateMatch, BatchDuplicatePartition, MediaDuplicateProof } from './MediaDuplicateProof';
import { MediaArtworkPipeline } from './MediaArtworkPipeline';
import { MediaFileChecker } from './MediaFileChecker';
import {
  FileCheckProgressCallback,
  ImportItemCallback,
  ImportLibraryChangedCallback,
  ImportProgressCallback,
  ImportRefreshPhase,
  ImportStartedCallback
} from './MediaImportCallbacks';
import { ImportPerformanceTrace } from './ImportPerformanceTrace';
import { RepositoryContentChangeKind } from '../data/RepositoryInvalidation';
import { DuplicatePolicy } from './DuplicatePolicy';
import { ImportDetailPolicy } from './ImportDetailPolicy';
import { ImportPreparationPolicy, PreparedItemState } from './ImportPreparationPolicy';
import {
  ImportProgress,
  ImportResult,
  ImportItemDetailKind,
  ImportItemOutcome,
  ImportItemResult,
  FileCheckResult,
  ParsedArtwork,
  ParsedMetadata
} from '../model/LibraryModels';
import {
  persistReadPermissions,
  revokeReadPermissions,
  selectAudioFiles
} from './MediaPickerService';
import { LibraryRemovalService } from '../maintenance/LibraryRemovalService';

interface ProgressNotificationGate {
  lastAt: number;
  intervalMs: number;
}

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
  cancelled?: boolean;
  trackId?: number;
  duplicateSource?: string;
  duplicateSourceUri?: string;
  errorMessage: string;
}

interface PendingArtworkWork {
  request: ArtworkWorkRequest;
}

export class MediaImportSession {
  private readonly context: common.UIAbilityContext;
  private readonly repository: MusicRepository;
  private readonly artworkCache: ArtworkCache;
  private readonly removalService: LibraryRemovalService;
  private readonly operation: MediaImportOperation;
  private readonly duplicateProof: MediaDuplicateProof;
  private readonly artworkPipeline: MediaArtworkPipeline;

  constructor(context: common.UIAbilityContext, repository: MusicRepository, artworkCache: ArtworkCache,
    operation: MediaImportOperation, artworkPipeline: MediaArtworkPipeline,
    removalService?: LibraryRemovalService) {
    this.context = context;
    this.repository = repository;
    this.artworkCache = artworkCache;
    this.operation = operation;
    this.duplicateProof = new MediaDuplicateProof(
      operation,
      (fileSize: number, quickFingerprint: string): Promise<Array<DuplicateCandidate>> =>
        repository.findDuplicateCandidates(fileSize, quickFingerprint),
      (uri: string): Promise<string> => calculateFullFingerprint(uri),
      (trackId: number, fingerprint: string): Promise<void> =>
        repository.updateFullFingerprint(trackId, fingerprint)
    );
    this.artworkPipeline = artworkPipeline;
    this.removalService = removalService === undefined ?
      new LibraryRemovalService(repository) : removalService;
  }

  private get cancelRequested(): boolean {
    return this.operation.isCancelled();
  }

  async selectAndImport(onProgress?: ImportProgressCallback,
    onStarted?: ImportStartedCallback, onItem?: ImportItemCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<ImportResult> {
    this.artworkPipeline.clearOperationContext();
    let completedResult: ImportResult | undefined;
    let traceStarted = false;
    let artworkSession: ArtworkWorkSession | undefined;
    try {
      await this.artworkPipeline.waitForCleanup();
      const uris = await selectAudioFiles(this.context);
      if (uris.length === 0) {
        return {
          imported: 0,
          duplicates: 0,
          failed: 0,
          artworkSkipped: 0,
          artworkFailed: 0,
          cancelled: false,
          items: []
        };
      }
      onStarted?.();
      artworkSession = this.createArtworkSession();
      ImportPerformanceTrace.start(uris.length);
      traceStarted = true;
      completedResult = await this.importUris(
        uris, artworkSession, onProgress, onItem, onLibraryChanged
      );
      return completedResult;
    } finally {
      if (artworkSession !== undefined) {
        await this.operation.cancelAndWait();
      }
      if (traceStarted) {
        ImportPerformanceTrace.event('cleanup_scheduled');
        const performance = ImportPerformanceTrace.finish(
          completedResult?.imported ?? 0,
          completedResult?.duplicates ?? 0,
          completedResult?.failed ?? 0
        );
        if (completedResult !== undefined) {
          completedResult.performance = performance;
        }
      }
      this.artworkPipeline.scheduleCleanup();
    }
  }

  async clearLibrary(): Promise<void> {
    await this.artworkPipeline.waitForCleanup();
    await this.removalService.clearLibrary();
    await this.artworkPipeline.scheduleCleanup();
  }

  async checkLibrary(onProgress?: FileCheckProgressCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<FileCheckResult> {
    const checker = new MediaFileChecker(
      this.repository,
      this.artworkCache,
      this.artworkPipeline,
      this.operation
    );
    return checker.checkLibrary(onProgress, onLibraryChanged);
  }

  private async importUris(uris: Array<string>, artworkSession: ArtworkWorkSession,
    onProgress?: ImportProgressCallback,
    onItem?: ImportItemCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<ImportResult> {
    const itemResults: Array<ImportItemResult> = [];
    const artworkWorks: Array<PendingArtworkWork> = [];
    const progress: ImportProgress = {
      total: uris.length,
      processed: 0,
      imported: 0,
      duplicates: 0,
      failed: 0,
      artworkTotal: 0,
      artworkProcessed: 0,
      artworkSkipped: 0,
      artworkFailed: 0,
      metadataCompleted: false,
      cancelled: false,
      currentName: '正在处理音乐文件'
    };
    const progressGate: ProgressNotificationGate = {
      lastAt: 0,
      intervalMs: ImportConcurrencyPolicy.IMPORT_PROGRESS_INTERVAL_MS
    };
    this.notify(onProgress, progress, progressGate, true);

    const pendingUris = await this.preflightUris(
      uris, itemResults, progress, progressGate, onProgress, onItem
    );
    for (let batchOffset = 0; batchOffset < pendingUris.length;
      batchOffset += ImportConcurrencyPolicy.IMPORT_WORK_BATCH_SIZE) {
      if (this.cancelRequested) {
        break;
      }
      const uriBatch = pendingUris.slice(
        batchOffset,
        Math.min(batchOffset + ImportConcurrencyPolicy.IMPORT_WORK_BATCH_SIZE, pendingUris.length)
      );
      const permissionStartedAt = Date.now();
      const permissionResult = await persistReadPermissions(uriBatch);
      if (this.cancelRequested) {
        await revokeReadPermissions(permissionResult.successfulUris);
        break;
      }
      ImportPerformanceTrace.mark('permission_persist', permissionStartedAt, 0,
        `count=${uriBatch.length} failed=${permissionResult.failedUris.length}`);
      progress.failed += permissionResult.failedUris.length;
      progress.processed += permissionResult.failedUris.length;
      permissionResult.failedUris.forEach((uri: string) => {
        this.recordItem(itemResults, {
          uri: uri,
          displayName: uri,
          outcome: ImportItemOutcome.FAILED,
          reason: '无法持久化文件读取授权',
          detailKind: ImportItemDetailKind.FAILED
        }, onItem);
      });
      this.notify(onProgress, progress, progressGate, true);

      const preparedInputs: Array<TrackImportInput> = [];
      const revokeAfterBatch: Array<string> = [];
      const prepareStartedAt = Date.now();
      const prepared = await this.prepareImports(permissionResult.successfulUris);
      if (this.cancelRequested) {
        await revokeReadPermissions(permissionResult.successfulUris);
        break;
      }
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
            reason: item.errorMessage.length > 0 ? item.errorMessage : '导入准备结果不完整',
            detailKind: ImportItemDetailKind.FAILED
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
            detailKind: ImportItemDetailKind.CONTENT_DUPLICATE,
            duplicateTrackId: item.duplicateTrackId,
            duplicateSourceUri: item.duplicateSourceUri
          }, onItem);
        } else {
          preparedInputs.push(item.input as TrackImportInput);
        }
        if ((index + 1) % ImportConcurrencyPolicy.FILE_CHECK_CLASSIFY_CHUNK_SIZE === 0) {
          this.notify(onProgress, progress, progressGate);
          await MediaImportSession.yieldToUi();
        }
      }
      this.notify(onProgress, progress, progressGate, true);

      if (this.cancelRequested) {
        await revokeReadPermissions(permissionResult.successfulUris);
        break;
      }
      if (preparedInputs.length > 0) {
        const batchProofStartedAt = Date.now();
        await this.ensureBatchFingerprintProofs(preparedInputs);
        ImportPerformanceTrace.mark('batch_duplicate_proof', batchProofStartedAt, 0,
          `count=${preparedInputs.length}`);
        if (this.cancelRequested) {
          await revokeReadPermissions(permissionResult.successfulUris);
          break;
        }
        const uniqueInputs = this.removeBatchDuplicates(
          preparedInputs, itemResults, progress, revokeAfterBatch, onItem
        );
        if (this.cancelRequested) {
          await revokeReadPermissions(permissionResult.successfulUris);
          break;
        }
        const databaseStartedAt = Date.now();
        const results = await this.commitPreparedInputs(uniqueInputs);
        ImportPerformanceTrace.mark('database_commit', databaseStartedAt, 0,
          `count=${uniqueInputs.length}`);
        ImportPerformanceTrace.markBatchAverage(
          'database_commit_per_file',
          databaseStartedAt,
          uniqueInputs.length
        );
        for (let index = 0; index < results.length; index += 1) {
          if (results[index].cancelled) {
            revokeAfterBatch.push(uniqueInputs[index].uri);
          } else if (results[index].failed) {
            progress.failed += 1;
            this.recordItem(itemResults, {
              uri: uniqueInputs[index].uri,
              displayName: uniqueInputs[index].displayName,
              outcome: ImportItemOutcome.FAILED,
              reason: results[index].errorMessage,
              detailKind: ImportItemDetailKind.FAILED
            }, onItem);
          } else if (results[index].imported) {
            progress.imported += 1;
            if (uniqueInputs[index].metadata.artworks.length > 0 &&
              results[index].trackId !== undefined) {
              progress.artworkTotal += 1;
              artworkWorks.push({
                request: {
                  trackId: results[index].trackId as number,
                  uri: uniqueInputs[index].uri,
                  fileSize: uniqueInputs[index].fileSize,
                  modifiedAt: uniqueInputs[index].modifiedAt,
                  metadata: uniqueInputs[index].metadata
                }
              });
            }
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
              detailKind: results[index].duplicateSource === 'content' ?
                ImportItemDetailKind.CONTENT_DUPLICATE : ImportItemDetailKind.URI_DUPLICATE,
              duplicateTrackId: results[index].trackId,
              duplicateSourceUri: results[index].duplicateSourceUri
            }, onItem);
          }
          if (results[index].failed) {
            revokeAfterBatch.push(uniqueInputs[index].uri);
          }
          if (!results[index].cancelled) {
            progress.processed += 1;
          }
          if ((index + 1) % ImportConcurrencyPolicy.FILE_CHECK_CLASSIFY_CHUNK_SIZE === 0) {
            this.notify(onProgress, progress, progressGate);
            await MediaImportSession.yieldToUi();
          }
        }
        this.notify(onProgress, progress, progressGate, true);
      }
      const revokeStartedAt = Date.now();
      await revokeReadPermissions(revokeAfterBatch);
      ImportPerformanceTrace.mark('permission_revoke', revokeStartedAt, 0,
        `count=${revokeAfterBatch.length}`);
    }
    const artworkPendingAtMetadataRefresh = artworkWorks.length > 0;
    progress.metadataCompleted = true;
    progress.cancelled = this.cancelRequested;
    progress.currentName = artworkPendingAtMetadataRefresh ?
      '正在处理封面' : '';
    this.notify(onProgress, progress, progressGate, true);
    if (progress.imported > 0) {
      await this.notifyLibraryChanged(onLibraryChanged, ImportRefreshPhase.METADATA);
    }
    artworkSession.startProcessing();
    let lastArtworkProgressAt = 0;
    await this.artworkPipeline.processWorks(
      artworkSession,
      artworkWorks.map((work: PendingArtworkWork): ArtworkWorkRequest => work.request),
      (_request: ArtworkWorkRequest, result: ArtworkWorkResult): void => {
        progress.artworkProcessed += 1;
        if (result.outcome === ArtworkWorkOutcome.SKIPPED) {
          progress.artworkSkipped += 1;
        } else if (result.outcome === ArtworkWorkOutcome.FAILED) {
          progress.artworkFailed += 1;
        }
        const now = Date.now();
        if (now - lastArtworkProgressAt >= ImportConcurrencyPolicy.IMPORT_PROGRESS_INTERVAL_MS ||
          progress.artworkProcessed >= progress.artworkTotal) {
          lastArtworkProgressAt = now;
          this.notify(onProgress, progress, progressGate, true);
        }
      }
    );
    await artworkSession.waitForIdle();
    progress.cancelled = progress.cancelled || this.cancelRequested ||
      artworkSession.isCancelled();
    if (progress.imported > 0 && artworkPendingAtMetadataRefresh) {
      await this.notifyLibraryChanged(onLibraryChanged, ImportRefreshPhase.ARTWORK);
    }
    progress.currentName = '';
    this.notify(onProgress, progress, progressGate, true);
    return {
      imported: progress.imported,
      duplicates: progress.duplicates,
      failed: progress.failed,
      artworkSkipped: progress.artworkSkipped,
      artworkFailed: progress.artworkFailed,
      cancelled: progress.cancelled,
      items: itemResults
    };
  }

  private async preflightUris(uris: Array<string>, itemResults: Array<ImportItemResult>,
    progress: ImportProgress, progressGate: ProgressNotificationGate,
    onProgress?: ImportProgressCallback,
    onItem?: ImportItemCallback): Promise<Array<string>> {
    const uniqueUris: Array<string> = [];
    const selectedUris: Set<string> = new Set();
    for (let index = 0; index < uris.length; index += 1) {
      const uri = uris[index];
      if (uri.length === 0) {
        progress.failed += 1;
        progress.processed += 1;
        this.recordItem(itemResults, {
          uri: uri,
          displayName: uri,
          outcome: ImportItemOutcome.FAILED,
          reason: '文件 URI 为空',
          detailKind: ImportItemDetailKind.FAILED
        }, onItem);
      } else if (selectedUris.has(uri)) {
        progress.duplicates += 1;
        progress.processed += 1;
        this.recordItem(itemResults, {
          uri: uri,
          displayName: uri,
          outcome: ImportItemOutcome.DUPLICATE,
          reason: '本次选择中存在相同文件 URI',
          detailKind: ImportItemDetailKind.BATCH_DUPLICATE,
          duplicateSourceUri: uri
        }, onItem);
      } else {
        selectedUris.add(uri);
        uniqueUris.push(uri);
      }
      if ((index + 1) % ImportConcurrencyPolicy.FILE_CHECK_CLASSIFY_CHUNK_SIZE === 0) {
        this.notify(onProgress, progress, progressGate);
        await MediaImportSession.yieldToUi();
      }
    }
    this.notify(onProgress, progress, progressGate, true);

    const pendingUris: Array<string> = [];
    for (let batchOffset = 0; batchOffset < uniqueUris.length;
      batchOffset += ImportConcurrencyPolicy.URI_PREFLIGHT_BATCH_SIZE) {
      if (this.cancelRequested) {
        break;
      }
      const uriBatch = uniqueUris.slice(
        batchOffset,
        Math.min(batchOffset + ImportConcurrencyPolicy.URI_PREFLIGHT_BATCH_SIZE, uniqueUris.length)
      );
      progress.currentName = '正在检查重复文件';
      this.notify(onProgress, progress, progressGate, true);
      const uriCheckStartedAt = Date.now();
      const existingUris = await this.repository.hasUris(uriBatch);
      const existingUriSet: Set<string> = new Set(existingUris);
      ImportPerformanceTrace.mark('uri_check', uriCheckStartedAt, 0,
        `batch=${batchOffset / ImportConcurrencyPolicy.URI_PREFLIGHT_BATCH_SIZE + 1} count=${uriBatch.length}`);
      for (let index = 0; index < uriBatch.length; index += 1) {
        const uri = uriBatch[index];
        if (existingUriSet.has(uri)) {
          progress.duplicates += 1;
          progress.processed += 1;
          this.recordItem(itemResults, {
            uri: uri,
            displayName: uri,
            outcome: ImportItemOutcome.DUPLICATE,
            reason: '同一文件 URI 已在音乐库中',
            detailKind: ImportItemDetailKind.URI_DUPLICATE,
            duplicateSourceUri: uri
          }, onItem);
        } else {
          pendingUris.push(uri);
        }
      }
      this.notify(onProgress, progress, progressGate, true);
      await MediaImportSession.yieldToUi();
    }
    return pendingUris;
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
        await MediaImportSession.yieldToUi();
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
      this.operation.throwIfCancelled();
      const candidateStartedAt = Date.now();
      const candidates = await this.findDuplicateCandidatesCached(
        readResult.fileSize, readResult.quickFingerprint
      );
      ImportPerformanceTrace.mark('candidate_query', candidateStartedAt, fileId,
        `count=${candidates.length}`);
      if (ImportConcurrencyPolicy.needsFullFingerprint(candidates.length, 1)) {
        const fingerprintStartedAt = Date.now();
        readResult.fullFingerprint = await calculateFullFingerprint(uri);
        this.operation.throwIfCancelled();
        ImportPerformanceTrace.mark('foreground_hash', fingerprintStartedAt, fileId,
          MediaImportSession.throughputDetails(readResult.fileSize, fingerprintStartedAt));
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
          artworks: MediaImportSession.artworkMetadataOnly(readResult.metadata.artworks)
        }
      };
      ImportPerformanceTrace.mark('file_prepare_total', totalStartedAt, fileId,
        `bytes=${readResult.fileSize} artworks=${readResult.metadata.artworks.length}`);
      return prepared;
    } catch (error) {
      const message = MediaImportSession.errorMessage(error);
      console.warn(`Music import failed: ${message}`);
      ImportPerformanceTrace.mark('file_prepare_failed', totalStartedAt, fileId);
      return { uri: uri, displayName: uri, errorMessage: message, failed: true, duplicate: false };
    }
  }

  private async findDuplicateCandidatesCached(fileSize: number,
    quickFingerprint: string): Promise<Array<DuplicateCandidate>> {
    try {
      return await this.duplicateProof.findCandidates(fileSize, quickFingerprint);
    } catch (error) {
      throw new Error(MediaImportSession.errorMessage(error));
    }
  }

  private async ensureCandidateFingerprints(candidates: Array<DuplicateCandidate>): Promise<void> {
    await this.duplicateProof.ensureCandidateFingerprints(candidates);
  }

  private async ensureBatchFingerprintProofs(inputs: Array<TrackImportInput>): Promise<void> {
    await this.duplicateProof.ensureBatchProofs(inputs);
  }

  private removeBatchDuplicates(inputs: Array<TrackImportInput>, itemResults: Array<ImportItemResult>,
    progress: ImportProgress, revokeAfterBatch: Array<string>,
    onItem?: ImportItemCallback): Array<TrackImportInput> {
    const partition: BatchDuplicatePartition =
      this.duplicateProof.partitionBatchDuplicates(inputs);
    for (let index = 0; index < partition.duplicates.length; index += 1) {
      const match: BatchDuplicateMatch = partition.duplicates[index];
      const input = match.duplicate;
      progress.duplicates += 1;
      progress.processed += 1;
      revokeAfterBatch.push(input.uri);
      this.recordItem(itemResults, {
        uri: input.uri,
        displayName: input.displayName,
        outcome: ImportItemOutcome.DUPLICATE,
        reason: '本批次中存在完整内容相同的文件',
        detailKind: ImportItemDetailKind.BATCH_DUPLICATE,
        duplicateSourceUri: match.source.uri
      }, onItem);
    }
    return partition.unique;
  }

  private async commitPreparedInputs(inputs: Array<TrackImportInput>): Promise<Array<CommitOutcome>> {
    if (this.cancelRequested || inputs.length === 0) {
      return [];
    }
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
      console.warn(`Batch import failed, retrying individually: ${MediaImportSession.errorMessage(error)}`);
      const results: Array<CommitOutcome> = [];
      for (let index = 0; index < inputs.length; index += 1) {
        if (this.cancelRequested) {
          results.push({
            imported: false,
            failed: false,
            cancelled: true,
            errorMessage: ''
          });
          continue;
        }
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
          const message = MediaImportSession.errorMessage(itemError);
          console.warn(`Music database write failed: ${message}`);
          results.push({ imported: false, failed: true, errorMessage: message });
        }
        await MediaImportSession.yieldToUi();
      }
      return results;
    }
  }

  private createArtworkSession(): ArtworkWorkSession {
    return this.artworkPipeline.createSession(this.operation);
  }

  private static artworkMetadataOnly(artworks: Array<ParsedArtwork>): Array<ArtworkImportInput> {
    return artworks.map((metadata: ParsedArtwork) => {
      const input: ArtworkImportInput = { metadata: metadata };
      return input;
    });
  }

  private notify(callback: ImportProgressCallback | undefined, progress: ImportProgress,
    gate?: ProgressNotificationGate, force: boolean = false): boolean {
    if (callback === undefined) {
      return false;
    }
    if (!MediaImportSession.shouldNotify(gate, force)) {
      return false;
    }
    callback({
      total: progress.total,
      processed: progress.processed,
      imported: progress.imported,
      duplicates: progress.duplicates,
      failed: progress.failed,
      artworkTotal: progress.artworkTotal,
      artworkProcessed: progress.artworkProcessed,
      artworkSkipped: progress.artworkSkipped,
      artworkFailed: progress.artworkFailed,
      metadataCompleted: progress.metadataCompleted,
      cancelled: progress.cancelled,
      currentName: progress.currentName
    });
    return true;
  }

  private async notifyLibraryChanged(callback: ImportLibraryChangedCallback | undefined,
    phase: ImportRefreshPhase): Promise<void> {
    this.repository.notifyContentChanged(phase === ImportRefreshPhase.METADATA ?
      RepositoryContentChangeKind.METADATA : RepositoryContentChangeKind.ARTWORK);
    if (callback === undefined) {
      return;
    }
    const startedAt = Date.now();
    try {
      await callback(phase);
      ImportPerformanceTrace.mark(`library_refresh_${phase}`, startedAt);
    } catch (error) {
      console.warn(`Library ${phase} refresh failed: ${MediaImportSession.errorMessage(error)}`);
    }
  }

  private recordItem(items: Array<ImportItemResult>, item: ImportItemResult,
    callback?: ImportItemCallback): void {
    if (ImportDetailPolicy.shouldRetain(item)) {
      items.push(item);
    }
    callback?.(item);
  }

  private static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  private static shouldNotify(gate: ProgressNotificationGate | undefined,
    force: boolean): boolean {
    if (gate === undefined) {
      return true;
    }
    const now = Date.now();
    if (!force && now - gate.lastAt < gate.intervalMs) {
      return false;
    }
    gate.lastAt = now;
    return true;
  }

  private static throughputDetails(byteSize: number, startedAt: number): string {
    const elapsed = Math.max(1, Date.now() - startedAt);
    const megabytesPerSecond = Math.round(byteSize * 1000 / elapsed / 1024 / 1024);
    return `bytes=${byteSize} mbps=${megabytesPerSecond}`;
  }

  private static yieldToUi(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 0);
    });
  }
}
