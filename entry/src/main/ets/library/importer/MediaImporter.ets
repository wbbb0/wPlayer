import { common } from '@kit.AbilityKit';
import { ArtworkCache, ArtworkCacheResult } from '../artwork/ArtworkCache';
import { ArtworkRepairPolicy } from '../artwork/ArtworkRepairPolicy';
import {
  ArtworkWorkCancellation,
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
import {
  calculateFullFingerprint,
  inspectMediaFiles,
  MediaFileInspectionInput,
  MediaFileInspectionResult,
  readArtworkBytesAsync
} from '../metadata/MediaFileTasks';
import { ImportConcurrencyPolicy } from './ImportConcurrencyPolicy';
import { ImportPerformanceTrace } from './ImportPerformanceTrace';
import { DuplicatePolicy } from './DuplicatePolicy';
import { ImportDetailPolicy } from './ImportDetailPolicy';
import { ImportPreparationPolicy, PreparedItemState } from './ImportPreparationPolicy';
import {
  ArtworkPictureType,
  ArtworkState,
  AvailabilityState,
  ImportProgress,
  ImportResult,
  ImportItemDetailKind,
  ImportItemOutcome,
  ImportItemResult,
  FileCheckProgress,
  FileCheckResult,
  FileCheckItemOutcome,
  FileCheckItemResult,
  MediaFileCheckCandidate,
  MetadataReadResult,
  ParsedArtwork,
  ParsedMetadata,
  TrackAvailabilityUpdate
} from '../model/LibraryModels';
import {
  persistReadPermissions,
  ReadPermissionProgress,
  revokeReadPermissions,
  ensureReadPermissions,
  selectAudioFiles
} from './MediaPickerService';

export type ImportProgressCallback = (progress: ImportProgress) => void;
export type ImportStartedCallback = () => void;
export type ImportItemCallback = (item: ImportItemResult) => void;
export type FileCheckProgressCallback = (progress: FileCheckProgress) => void;
export enum ImportRefreshPhase {
  METADATA = 'metadata',
  ARTWORK = 'artwork'
}
export type ImportLibraryChangedCallback = (phase: ImportRefreshPhase) => Promise<void>;

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

interface FileCheckWorkResult {
  updated: boolean;
  unavailable: boolean;
  recovered: boolean;
  artworkRebuilt: boolean;
  item?: FileCheckItemResult;
  availabilityUpdate?: TrackAvailabilityUpdate;
  artworkTask?: Promise<ArtworkWorkResult>;
  artworkItem?: FileCheckItemResult;
}

export class MediaImporter {
  private readonly context: common.UIAbilityContext;
  private readonly repository: MusicRepository;
  private readonly artworkCache: ArtworkCache;
  private cancelRequested: boolean = false;
  private importing: boolean = false;
  private readonly artworkPreparations: Map<string, Promise<ArtworkCacheResult>> = new Map();
  private readonly duplicateCandidateLookups: Map<string, Promise<Array<DuplicateCandidate>>> = new Map();
  private readonly candidateFingerprintTasks: Map<number, Promise<string>> = new Map();
  private artworkCleanupTail: Promise<void> = Promise.resolve();
  private activeArtworkSession?: ArtworkWorkSession;

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
    this.activeArtworkSession?.cancel();
  }

  async selectAndImport(onProgress?: ImportProgressCallback,
    onStarted?: ImportStartedCallback, onItem?: ImportItemCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<ImportResult> {
    if (this.importing) {
      throw new Error('An import is already running');
    }
    this.importing = true;
    this.cancelRequested = false;
    this.artworkPreparations.clear();
    this.duplicateCandidateLookups.clear();
    this.candidateFingerprintTasks.clear();
    let completedResult: ImportResult | undefined;
    let traceStarted = false;
    let artworkSession: ArtworkWorkSession | undefined;
    try {
      await this.artworkCleanupTail;
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
      this.activeArtworkSession = artworkSession;
      ImportPerformanceTrace.start(uris.length);
      traceStarted = true;
      completedResult = await this.importUris(
        uris, artworkSession, onProgress, onItem, onLibraryChanged
      );
      return completedResult;
    } finally {
      if (artworkSession !== undefined) {
        artworkSession.cancel();
        await artworkSession.waitForIdle();
        if (this.activeArtworkSession === artworkSession) {
          this.activeArtworkSession = undefined;
        }
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
      this.importing = false;
      this.cancelRequested = false;
      this.artworkPreparations.clear();
      this.duplicateCandidateLookups.clear();
      this.candidateFingerprintTasks.clear();
      this.scheduleArtworkCleanup();
    }
  }

  async clearLibrary(): Promise<void> {
    if (this.importing) {
      throw new Error('Cannot clear the library during an import');
    }
    await this.artworkCleanupTail;
    await this.repository.clearLibrary();
    const assets = await this.repository.getUnreferencedArtworkAssets();
    for (let index = 0; index < assets.length; index += 1) {
      const asset = assets[index];
      if (asset.deleteSmall) {
        await this.artworkCache.deleteAsync(asset.smallPath);
      }
      if (asset.deleteLarge) {
        await this.artworkCache.deleteAsync(asset.largePath);
      }
      await this.repository.removeUnreferencedArtwork(asset.assetId);
    }
    this.scheduleArtworkCleanup();
  }

  async checkLibrary(onProgress?: FileCheckProgressCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<FileCheckResult> {
    if (this.importing) {
      throw new Error('Cannot check music files during an import');
    }
    this.importing = true;
    this.cancelRequested = false;
    this.artworkPreparations.clear();
    const artworkSession = this.createArtworkSession();
    this.activeArtworkSession = artworkSession;
    let progress: FileCheckProgress = {
      total: 0,
      processed: 0,
      updated: 0,
      unavailable: 0,
      recovered: 0,
      artworkRebuilt: 0,
      artworkTotal: 0,
      artworkProcessed: 0,
      artworkSkipped: 0,
      artworkFailed: 0,
      metadataCompleted: false,
      cancelled: false,
      currentName: ''
    };
    try {
      const candidates = await this.repository.getMediaFileCheckCandidates();
      progress = {
      total: candidates.length,
      processed: 0,
      updated: 0,
      unavailable: 0,
      recovered: 0,
      artworkRebuilt: 0,
      artworkTotal: 0,
      artworkProcessed: 0,
      artworkSkipped: 0,
      artworkFailed: 0,
      metadataCompleted: false,
      cancelled: false,
      currentName: ''
      };
      this.notifyFileCheck(onProgress, progress);
      const startedAt = Date.now();
      progress.currentName = '正在激活文件访问权限';
      this.notifyFileCheck(onProgress, progress);
      const permissionStartedAt = Date.now();
      const permissions = await ensureReadPermissions(
        candidates.map((candidate: MediaFileCheckCandidate): string => candidate.uri),
        (permissionProgress: ReadPermissionProgress): void => {
          progress.currentName = `正在激活文件访问权限 ` +
            `${permissionProgress.processed} / ${permissionProgress.total}`;
          this.notifyFileCheck(onProgress, progress);
          console.info(`[FileCheck] permission batch ${permissionProgress.processed}/` +
            `${permissionProgress.total} in ${permissionProgress.batchDurationMs}ms`);
        }
      );
      const accessibleUris = new Set<string>(permissions.successfulUris);
      const availabilityUpdates: Array<TrackAvailabilityUpdate> = [];
      const itemResults: Array<FileCheckItemResult> = [];
      const accessibleCandidates: Array<MediaFileCheckCandidate> = [];
      const classifyStartedAt = Date.now();
      for (let index = 0; index < candidates.length; index += 1) {
        const candidate = candidates[index];
        if (accessibleUris.has(candidate.uri)) {
          accessibleCandidates.push(candidate);
        } else {
          availabilityUpdates.push({
            trackId: candidate.trackId,
            state: AvailabilityState.AUTHORIZATION_REVOKED
          });
          itemResults.push({
            trackId: candidate.trackId,
            displayName: candidate.displayName,
            uri: candidate.uri,
            outcome: FileCheckItemOutcome.AUTHORIZATION_REVOKED,
            reason: '文件读取授权已失效'
          });
          progress.processed += 1;
          progress.unavailable += 1;
        }
        if ((index + 1) % ImportConcurrencyPolicy.FILE_CHECK_CLASSIFY_CHUNK_SIZE === 0) {
          progress.currentName = `正在整理待检查文件 ${index + 1} / ${candidates.length}`;
          this.notifyFileCheck(onProgress, progress);
          await MediaImporter.yieldToUi();
        }
      }
      console.info(`[FileCheck] classified ${candidates.length} candidates in ` +
        `${Date.now() - classifyStartedAt}ms`);
      console.info(`[FileCheck] permissions ${Date.now() - permissionStartedAt}ms, ` +
        `available=${accessibleCandidates.length}, failed=${permissions.failedUris.length}`);
      let lastProgressAt = 0;
      let prefetchedInspections: Promise<Array<MediaFileInspectionResult>> | undefined;
      if (accessibleCandidates.length > 0 && !this.cancelRequested) {
        const firstBatch = accessibleCandidates.slice(
          0,
          Math.min(ImportConcurrencyPolicy.FILE_CHECK_BATCH_SIZE, accessibleCandidates.length)
        );
        prefetchedInspections = inspectMediaFiles(this.createFileInspectionInputs(firstBatch));
      }
      for (let offset = 0; offset < accessibleCandidates.length &&
        !this.cancelRequested; offset += ImportConcurrencyPolicy.FILE_CHECK_BATCH_SIZE) {
        const batch = accessibleCandidates.slice(
          offset,
          Math.min(offset + ImportConcurrencyPolicy.FILE_CHECK_BATCH_SIZE, accessibleCandidates.length)
        );
        const currentInspections = prefetchedInspections;
        if (currentInspections === undefined) {
          throw new Error('File inspection pipeline lost its current batch');
        }
        const nextOffset = offset + ImportConcurrencyPolicy.FILE_CHECK_BATCH_SIZE;
        if (nextOffset < accessibleCandidates.length && !this.cancelRequested) {
          const nextBatch = accessibleCandidates.slice(
            nextOffset,
            Math.min(
              nextOffset + ImportConcurrencyPolicy.FILE_CHECK_BATCH_SIZE,
              accessibleCandidates.length
            )
          );
          prefetchedInspections = inspectMediaFiles(this.createFileInspectionInputs(nextBatch));
        } else {
          prefetchedInspections = undefined;
        }
        progress.currentName = `正在后台检查音乐文件 ` +
          `${offset} / ${accessibleCandidates.length}`;
        this.notifyFileCheck(onProgress, progress);
        const inspectionStartedAt = Date.now();
        const inspections = await currentInspections;
        console.info(`[FileCheck] inspected batch ${offset + batch.length}/` +
          `${accessibleCandidates.length} in ${Date.now() - inspectionStartedAt}ms`);
        for (let index = 0; index < batch.length; index += 1) {
          const outcome = await this.checkOneFile(
            batch[index], inspections[index], artworkSession
          );
          if (outcome.updated) {
            progress.updated += 1;
          }
          if (outcome.unavailable) {
            progress.unavailable += 1;
          }
          if (outcome.recovered) {
            progress.recovered += 1;
          }
          if (outcome.artworkRebuilt) {
            progress.artworkRebuilt += 1;
          }
          if (outcome.artworkTask !== undefined) {
            progress.artworkTotal += 1;
            outcome.artworkTask.then((artworkResult: ArtworkWorkResult): void => {
              progress.artworkProcessed += 1;
              if (artworkResult.outcome === ArtworkWorkOutcome.COMPLETED) {
                if (artworkResult.sourceHasArtwork) {
                  progress.artworkRebuilt += 1;
                }
                if (outcome.artworkItem !== undefined) {
                  itemResults.push({
                    trackId: outcome.artworkItem.trackId,
                    displayName: outcome.artworkItem.displayName,
                    uri: outcome.artworkItem.uri,
                    outcome: artworkResult.sourceHasArtwork ?
                      outcome.artworkItem.outcome : FileCheckItemOutcome.ARTWORK_ABSENT,
                    reason: artworkResult.sourceHasArtwork ?
                      outcome.artworkItem.reason : '已确认源文件没有封面'
                  });
                }
              } else if (artworkResult.outcome === ArtworkWorkOutcome.SKIPPED) {
                progress.artworkSkipped += 1;
              } else if (artworkResult.outcome === ArtworkWorkOutcome.FAILED) {
                progress.artworkFailed += 1;
                if (outcome.artworkItem !== undefined) {
                  itemResults.push({
                    trackId: outcome.artworkItem.trackId,
                    displayName: outcome.artworkItem.displayName,
                    uri: outcome.artworkItem.uri,
                    outcome: FileCheckItemOutcome.ARTWORK_FAILED,
                    reason: artworkResult.errorMessage.length > 0 ?
                      artworkResult.errorMessage : '封面处理失败'
                  });
                }
              }
              if (progress.metadataCompleted) {
                this.notifyFileCheck(onProgress, progress);
              }
            });
          }
          if (outcome.item !== undefined) {
            itemResults.push(outcome.item);
          }
          if (outcome.availabilityUpdate !== undefined) {
            availabilityUpdates.push(outcome.availabilityUpdate);
          }
          progress.processed += 1;
          const now = Date.now();
          if (now - lastProgressAt >= 100 || progress.processed >= progress.total) {
            lastProgressAt = now;
            this.notifyFileCheck(onProgress, progress);
          }
        }
        await MediaImporter.yieldToUi();
      }
      if (this.cancelRequested && prefetchedInspections !== undefined) {
        try {
          await prefetchedInspections;
        } catch (_) {
        }
      }
      progress.currentName = '正在保存检查结果';
      this.notifyFileCheck(onProgress, progress);
      await this.repository.setTrackAvailabilities(availabilityUpdates);
      const artworkWasScheduled = progress.artworkTotal > 0;
      progress.metadataCompleted = true;
      progress.cancelled = this.cancelRequested;
      progress.currentName = artworkWasScheduled ? '正在处理封面' : '';
      this.notifyFileCheck(onProgress, progress);
      await this.notifyLibraryChanged(onLibraryChanged, ImportRefreshPhase.METADATA);
      artworkSession.startProcessing();
      await artworkSession.waitForIdle();
      progress.cancelled = progress.cancelled || this.cancelRequested ||
        artworkSession.isCancelled();
      if (artworkWasScheduled) {
        await this.notifyLibraryChanged(onLibraryChanged, ImportRefreshPhase.ARTWORK);
      }
      progress.currentName = '';
      this.notifyFileCheck(onProgress, progress);
      console.info(`[FileCheck] completed ${progress.processed}/${progress.total} in ` +
        `${Date.now() - startedAt}ms, updated=${progress.updated}, unavailable=${progress.unavailable}, ` +
        `recovered=${progress.recovered}`);
      return {
        checked: progress.processed,
        updated: progress.updated,
        unavailable: progress.unavailable,
        recovered: progress.recovered,
        artworkRebuilt: progress.artworkRebuilt,
        artworkSkipped: progress.artworkSkipped,
        artworkFailed: progress.artworkFailed,
        cancelled: progress.cancelled,
        items: itemResults
      };
    } finally {
      artworkSession.cancel();
      await artworkSession.waitForIdle();
      if (this.activeArtworkSession === artworkSession) {
        this.activeArtworkSession = undefined;
      }
      this.importing = false;
      this.cancelRequested = false;
      this.artworkPreparations.clear();
      this.scheduleArtworkCleanup();
    }
  }

  private async checkOneFile(candidate: MediaFileCheckCandidate,
    inspection: MediaFileInspectionResult,
    artworkSession: ArtworkWorkSession): Promise<FileCheckWorkResult> {
    if (!inspection.available) {
      return {
        updated: false,
        unavailable: true,
        recovered: false,
        artworkRebuilt: false,
        availabilityUpdate: {
          trackId: candidate.trackId,
          state: AvailabilityState.UNAVAILABLE
        },
        item: {
          trackId: candidate.trackId,
          displayName: candidate.displayName,
          uri: candidate.uri,
          outcome: FileCheckItemOutcome.UNAVAILABLE,
          reason: '无法打开音乐文件'
        }
      };
    }
    if (inspection.fileSize === candidate.fileSize &&
      inspection.modifiedAt === candidate.modifiedAt) {
      if (candidate.availability === AvailabilityState.AVAILABLE) {
        if (!this.needsArtworkRepair(candidate, inspection.artworkFilesAvailable)) {
          return { updated: false, unavailable: false, recovered: false, artworkRebuilt: false };
        }
        return this.repairArtwork(candidate, artworkSession);
      }
      let artworkTask: Promise<ArtworkWorkResult> | undefined;
      let artworkItem: FileCheckItemResult | undefined;
      if (this.needsArtworkRepair(candidate, inspection.artworkFilesAvailable)) {
        const repairResult = this.repairArtwork(candidate, artworkSession);
        artworkTask = repairResult.artworkTask;
        artworkItem = repairResult.artworkItem;
      }
      return {
        updated: false,
        unavailable: false,
        recovered: true,
        artworkRebuilt: false,
        artworkTask: artworkTask,
        artworkItem: artworkItem,
        availabilityUpdate: {
          trackId: candidate.trackId,
          state: AvailabilityState.AVAILABLE
        },
        item: {
          trackId: candidate.trackId,
          displayName: candidate.displayName,
          uri: candidate.uri,
          outcome: FileCheckItemOutcome.RECOVERED,
          reason: '文件已恢复可用'
        }
      };
    }
    try {
      const readResult = await MetadataReader.read(candidate.uri);
      await this.repository.refreshTrack(candidate.trackId, {
        uri: candidate.uri,
        displayName: readResult.fileName,
        fileSize: readResult.fileSize,
        modifiedAt: readResult.modifiedAt,
        quickFingerprint: readResult.quickFingerprint,
        fullFingerprint: '',
        authorizationPersisted: true,
        metadata: readResult.metadata,
        artworks: MediaImporter.artworkMetadataOnly(readResult.metadata.artworks)
      });
      let artworkTask: Promise<ArtworkWorkResult> | undefined;
      let artworkItem: FileCheckItemResult | undefined;
      if (readResult.metadata.artworks.length > 0) {
        artworkTask = artworkSession.enqueue({
          trackId: candidate.trackId,
          uri: candidate.uri,
          fileSize: readResult.fileSize,
          modifiedAt: readResult.modifiedAt,
          metadata: readResult.metadata
        });
        artworkItem = {
          trackId: candidate.trackId,
          displayName: readResult.fileName,
          uri: candidate.uri,
          outcome: FileCheckItemOutcome.ARTWORK_REBUILT,
          reason: '文件变化后的封面已更新'
        };
      }
      return {
        updated: true,
        unavailable: false,
        recovered: candidate.availability !== AvailabilityState.AVAILABLE,
        artworkRebuilt: false,
        artworkTask: artworkTask,
        artworkItem: artworkItem,
        item: {
          trackId: candidate.trackId,
          displayName: readResult.fileName,
          uri: candidate.uri,
          outcome: FileCheckItemOutcome.UPDATED,
          reason: '文件已变化，音乐信息已更新'
        }
      };
    } catch (error) {
      console.warn(`Unable to refresh ${candidate.displayName}: ${MediaImporter.errorMessage(error)}`);
      return {
        updated: false,
        unavailable: true,
        recovered: false,
        artworkRebuilt: false,
        availabilityUpdate: {
          trackId: candidate.trackId,
          state: AvailabilityState.CORRUPTED
        },
        item: {
          trackId: candidate.trackId,
          displayName: candidate.displayName,
          uri: candidate.uri,
          outcome: FileCheckItemOutcome.CORRUPTED,
          reason: '文件已变化，但无法重新解析'
        }
      };
    }
  }

  async cleanupArtworkStorage(): Promise<void> {
    this.scheduleArtworkCleanup();
  }

  private async importUris(uris: Array<string>, artworkSession: ArtworkWorkSession,
    onProgress?: ImportProgressCallback,
    onItem?: ImportItemCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<ImportResult> {
    const itemResults: Array<ImportItemResult> = [];
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
    this.notify(onProgress, progress);

    const pendingUris = await this.preflightUris(uris, itemResults, progress, onProgress, onItem);
    for (let batchOffset = 0; batchOffset < pendingUris.length;
      batchOffset += ImportConcurrencyPolicy.IMPORT_WORK_BATCH_SIZE) {
      if (this.cancelRequested) {
        break;
      }
      this.duplicateCandidateLookups.clear();
      const uriBatch = pendingUris.slice(
        batchOffset,
        Math.min(batchOffset + ImportConcurrencyPolicy.IMPORT_WORK_BATCH_SIZE, pendingUris.length)
      );
      const permissionStartedAt = Date.now();
      const permissionResult = await persistReadPermissions(uriBatch);
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
      this.notify(onProgress, progress);

      const preparedInputs: Array<TrackImportInput> = [];
      const revokeAfterBatch: Array<string> = [];
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
      }
      this.notify(onProgress, progress);

      if (this.cancelRequested) {
        await revokeReadPermissions(permissionResult.successfulUris);
        break;
      }
      if (preparedInputs.length > 0) {
        const batchProofStartedAt = Date.now();
        await this.ensureBatchFingerprintProofs(preparedInputs);
        ImportPerformanceTrace.mark('batch_duplicate_proof', batchProofStartedAt, 0,
          `count=${preparedInputs.length}`);
        const uniqueInputs = this.removeBatchDuplicates(
          preparedInputs, itemResults, progress, revokeAfterBatch, onItem
        );
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
          if (results[index].failed) {
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
              const artworkTask = artworkSession.enqueue({
                trackId: results[index].trackId as number,
                uri: uniqueInputs[index].uri,
                fileSize: uniqueInputs[index].fileSize,
                modifiedAt: uniqueInputs[index].modifiedAt,
                metadata: uniqueInputs[index].metadata
              });
              artworkTask.then((result: ArtworkWorkResult): void => {
                progress.artworkProcessed += 1;
                if (result.outcome === ArtworkWorkOutcome.SKIPPED) {
                  progress.artworkSkipped += 1;
                } else if (result.outcome === ArtworkWorkOutcome.FAILED) {
                  progress.artworkFailed += 1;
                }
                if (progress.metadataCompleted) {
                  this.notify(onProgress, progress);
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
          progress.processed += 1;
        }
        this.notify(onProgress, progress);
      }
      const revokeStartedAt = Date.now();
      await revokeReadPermissions(revokeAfterBatch);
      ImportPerformanceTrace.mark('permission_revoke', revokeStartedAt, 0,
        `count=${revokeAfterBatch.length}`);
    }
    const artworkPendingAtMetadataRefresh = artworkSession.hasScheduledWork();
    progress.metadataCompleted = true;
    progress.cancelled = this.cancelRequested;
    progress.currentName = artworkPendingAtMetadataRefresh ?
      '正在处理封面' : '';
    this.notify(onProgress, progress);
    if (progress.imported > 0) {
      await this.notifyLibraryChanged(onLibraryChanged, ImportRefreshPhase.METADATA);
    }
    artworkSession.startProcessing();
    await artworkSession.waitForIdle();
    progress.cancelled = progress.cancelled || this.cancelRequested ||
      artworkSession.isCancelled();
    if (progress.imported > 0 && artworkPendingAtMetadataRefresh) {
      await this.notifyLibraryChanged(onLibraryChanged, ImportRefreshPhase.ARTWORK);
    }
    progress.currentName = '';
    this.notify(onProgress, progress);
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
    progress: ImportProgress, onProgress?: ImportProgressCallback,
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
    }
    this.notify(onProgress, progress);

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
      this.notify(onProgress, progress);
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
      this.notify(onProgress, progress);
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
      const candidates = await this.findDuplicateCandidatesCached(
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

  private async findDuplicateCandidatesCached(fileSize: number,
    quickFingerprint: string): Promise<Array<DuplicateCandidate>> {
    const key = `${fileSize}:${quickFingerprint}`;
    const existing = this.duplicateCandidateLookups.get(key);
    if (existing !== undefined) {
      return existing;
    }
    const pending = this.repository.findDuplicateCandidates(fileSize, quickFingerprint);
    this.duplicateCandidateLookups.set(key, pending);
    try {
      return await pending;
    } catch (error) {
      if (this.duplicateCandidateLookups.get(key) === pending) {
        this.duplicateCandidateLookups.delete(key);
      }
      throw new Error(MediaImporter.errorMessage(error));
    }
  }

  private async ensureCandidateFingerprints(candidates: Array<DuplicateCandidate>): Promise<void> {
    for (let index = 0; index < candidates.length; index += 1) {
      const candidate = candidates[index];
      if (candidate.fullFingerprint.length > 0) {
        continue;
      }
      const existing = this.candidateFingerprintTasks.get(candidate.trackId);
      let pending: Promise<string>;
      if (existing !== undefined) {
        pending = existing;
      } else {
        pending = this.calculateAndPersistCandidateFingerprint(candidate);
        this.candidateFingerprintTasks.set(candidate.trackId, pending);
      }
      try {
        candidate.fullFingerprint = await pending;
      } catch (error) {
        if (this.candidateFingerprintTasks.get(candidate.trackId) === pending) {
          this.candidateFingerprintTasks.delete(candidate.trackId);
        }
        throw new Error(MediaImporter.errorMessage(error));
      }
    }
  }

  private async calculateAndPersistCandidateFingerprint(candidate: DuplicateCandidate): Promise<string> {
    const fileId = ImportPerformanceTrace.fileId(candidate.uri);
    const startedAt = Date.now();
    const fingerprint = await calculateFullFingerprint(candidate.uri);
    ImportPerformanceTrace.mark('candidate_hash', startedAt, fileId);
    await this.repository.updateFullFingerprint(candidate.trackId, fingerprint);
    return fingerprint;
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
    const pendingInputs: Array<TrackImportInput> = [];
    groups.forEach((group: Array<TrackImportInput>) => {
      if (!ImportConcurrencyPolicy.needsFullFingerprint(0, group.length)) {
        return;
      }
      group.forEach((input: TrackImportInput) => {
        if (input.fullFingerprint.length === 0) {
          pendingInputs.push(input);
        }
      });
    });
    let nextIndex = 0;
    const consume = async (): Promise<void> => {
      while (nextIndex < pendingInputs.length) {
        const input = pendingInputs[nextIndex++];
        const fileId = ImportPerformanceTrace.fileId(input.uri);
        const startedAt = Date.now();
        input.fullFingerprint = await calculateFullFingerprint(input.uri);
        ImportPerformanceTrace.mark('batch_hash', startedAt, fileId,
          MediaImporter.throughputDetails(input.fileSize, startedAt));
      }
    };
    const workers: Array<Promise<void>> = [];
    const workerCount = Math.min(
      ImportConcurrencyPolicy.FULL_FINGERPRINT_CONCURRENCY,
      pendingInputs.length
    );
    for (let index = 0; index < workerCount; index += 1) {
      workers.push(consume());
    }
    await Promise.all(workers);
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
        detailKind: ImportItemDetailKind.BATCH_DUPLICATE,
        duplicateSourceUri: source.uri
      }, onItem);
    }
    return unique;
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

  private async prepareArtworks(uri: string, metadata: ParsedMetadata,
    cancellation?: ArtworkWorkCancellation): Promise<Array<ArtworkImportInput>> {
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
    MediaImporter.throwIfArtworkCancelled(cancellation);
    const sourceBytes = new Uint8Array(sourceBuffer);
    const hashStartedAt = Date.now();
    const sourceHash = await ArtworkCache.hashSource(sourceBytes);
    ImportPerformanceTrace.mark('artwork_hash', hashStartedAt, fileId,
      `bytes=${sourceBytes.byteLength}`);
    MediaImporter.throwIfArtworkCancelled(cancellation);
    const cached = await this.loadOrCacheArtwork(
      sourceHash, sourceBytes, fileId,
      (): boolean => cancellation === undefined || !cancellation.isCancelled()
    );
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
      palettePrimary: cached.palette.primary,
      paletteSecondary: cached.palette.secondary,
      paletteAccent: cached.palette.accent,
      primary: true
    };
    return inputs;
  }

  private async loadOrCacheArtwork(sourceHash: string, sourceBytes: Uint8Array,
    traceFileId: number, shouldContinue?: () => boolean): Promise<ArtworkCacheResult> {
    const activePreparation = this.artworkPreparations.get(sourceHash);
    if (activePreparation !== undefined) {
      return activePreparation;
    }
    const preparation = this.resolveArtwork(
      sourceHash, sourceBytes, traceFileId, shouldContinue
    );
    this.artworkPreparations.set(sourceHash, preparation);
    try {
      return await preparation;
    } catch (error) {
      if (this.artworkPreparations.get(sourceHash) === preparation) {
        this.artworkPreparations.delete(sourceHash);
      }
      throw new Error(MediaImporter.errorMessage(error));
    } finally {
      this.trimArtworkPreparations();
    }
  }

  private trimArtworkPreparations(): void {
    const maximumEntries = 128;
    while (this.artworkPreparations.size > maximumEntries) {
      const oldest = this.artworkPreparations.keys().next();
      if (oldest.done) {
        return;
      }
      this.artworkPreparations.delete(oldest.value);
    }
  }

  private async resolveArtwork(sourceHash: string, sourceBytes: Uint8Array,
    traceFileId: number, shouldContinue?: () => boolean): Promise<ArtworkCacheResult> {
    const lookupStartedAt = Date.now();
    const existing = await this.repository.findArtworkBySourceHash(sourceHash);
    if (existing !== undefined && await this.artworkCache.existsAsync(existing.smallPath) &&
      await this.artworkCache.existsAsync(existing.largePath)) {
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
        },
        palette: {
          primary: existing.palettePrimary,
          secondary: existing.paletteSecondary,
          accent: existing.paletteAccent
        }
      };
    }
    ImportPerformanceTrace.mark('artwork_cache_lookup', lookupStartedAt, traceFileId, 'hit=0');
    return this.artworkCache.cache(
      sourceBytes, sourceHash, traceFileId, shouldContinue
    );
  }

  private needsArtworkRepair(candidate: MediaFileCheckCandidate, filesAvailable: boolean): boolean {
    return ArtworkRepairPolicy.needsRepair(
      candidate.artworkState,
      filesAvailable,
      filesAvailable,
      candidate.artworkAttemptCount,
      candidate.artworkLastAttemptAt
    );
  }

  private createFileInspectionInputs(
    candidates: Array<MediaFileCheckCandidate>
  ): Array<MediaFileInspectionInput> {
    return candidates.map(
      (candidate: MediaFileCheckCandidate): MediaFileInspectionInput => {
        const checkArtworkFiles = candidate.artworkState === ArtworkState.READY &&
          candidate.artworkSmallPath.length > 0 && candidate.artworkLargePath.length > 0;
        return {
          uri: candidate.uri,
          artworkSmallPath: checkArtworkFiles ?
            this.artworkCache.resolvePath(candidate.artworkSmallPath) : '',
          artworkLargePath: checkArtworkFiles ?
            this.artworkCache.resolvePath(candidate.artworkLargePath) : ''
        };
      }
    );
  }

  private repairArtwork(candidate: MediaFileCheckCandidate,
    artworkSession: ArtworkWorkSession): FileCheckWorkResult {
    const artworkTask = artworkSession.enqueue({
      trackId: candidate.trackId,
      uri: candidate.uri,
      fileSize: candidate.fileSize,
      modifiedAt: candidate.modifiedAt
    });
    return {
      updated: false,
      unavailable: false,
      recovered: false,
      artworkRebuilt: false,
      artworkTask: artworkTask,
      artworkItem: {
        trackId: candidate.trackId,
        displayName: candidate.displayName,
        uri: candidate.uri,
        outcome: FileCheckItemOutcome.ARTWORK_REBUILT,
        reason: '缺失封面已重建'
      }
    };
  }

  private createArtworkSession(): ArtworkWorkSession {
    return new ArtworkWorkSession(
      (request: ArtworkWorkRequest,
        cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> =>
        this.processArtworkItem(request, cancellation),
      false
    );
  }

  private async processArtworkItem(item: ArtworkWorkRequest,
    cancellation: ArtworkWorkCancellation): Promise<ArtworkWorkResult> {
    if (cancellation.isCancelled()) {
      return MediaImporter.artworkWorkResult(ArtworkWorkOutcome.SKIPPED);
    }
    let metadata = item.metadata;
    try {
      const startedAt = Date.now();
      if (metadata === undefined) {
        const metadataStartedAt = Date.now();
        const readResult = await MetadataReader.read(item.uri);
        ImportPerformanceTrace.mark(
          'artwork_metadata_read',
          metadataStartedAt,
          ImportPerformanceTrace.fileId(item.uri)
        );
        if (readResult.fileSize !== item.fileSize || readResult.modifiedAt !== item.modifiedAt) {
          return MediaImporter.artworkWorkResult(ArtworkWorkOutcome.STALE);
        }
        metadata = readResult.metadata;
      }
      if (cancellation.isCancelled()) {
        return MediaImporter.artworkWorkResult(ArtworkWorkOutcome.SKIPPED);
      }
      const accepted = await this.repository.markArtworkProcessing(
        item.trackId, item.fileSize, item.modifiedAt
      );
      if (!accepted) {
        return MediaImporter.artworkWorkResult(ArtworkWorkOutcome.STALE);
      }
      const artworks = await this.prepareArtworks(item.uri, metadata, cancellation);
      if (cancellation.isCancelled()) {
        await this.repository.deferArtwork(item.trackId, item.fileSize, item.modifiedAt);
        return MediaImporter.artworkWorkResult(ArtworkWorkOutcome.SKIPPED);
      }
      if (!await this.mediaSnapshotMatches(item)) {
        await this.repository.deferArtwork(item.trackId, item.fileSize, item.modifiedAt);
        return MediaImporter.artworkWorkResult(ArtworkWorkOutcome.STALE);
      }
      if (cancellation.isCancelled()) {
        await this.repository.deferArtwork(item.trackId, item.fileSize, item.modifiedAt);
        return MediaImporter.artworkWorkResult(ArtworkWorkOutcome.SKIPPED);
      }
      const completed = await this.repository.completeArtwork(
        item.trackId, item.fileSize, item.modifiedAt, artworks
      );
      ImportPerformanceTrace.mark(
        'artwork_total', startedAt, ImportPerformanceTrace.fileId(item.uri),
        `count=${metadata.artworks.length}`
      );
      return MediaImporter.artworkWorkResult(
        completed ? ArtworkWorkOutcome.COMPLETED : ArtworkWorkOutcome.STALE,
        metadata.artworks.length > 0
      );
    } catch (error) {
      const message = MediaImporter.errorMessage(error);
      console.warn(`Artwork queue failed for track ${item.trackId}: ${message}`);
      if (cancellation.isCancelled()) {
        await this.repository.deferArtwork(item.trackId, item.fileSize, item.modifiedAt);
        return MediaImporter.artworkWorkResult(ArtworkWorkOutcome.SKIPPED);
      }
      await this.repository.failArtwork(item.trackId, item.fileSize, item.modifiedAt, message);
      return MediaImporter.artworkWorkResult(
        ArtworkWorkOutcome.FAILED,
        metadata !== undefined && metadata.artworks.length > 0,
        message
      );
    }
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

  private async cleanupArtworkFiles(): Promise<void> {
    const shouldContinue = (): boolean =>
      !this.importing && this.activeArtworkSession === undefined;
    if (!shouldContinue()) {
      return;
    }
    const referencedPaths = await this.repository.getReferencedArtworkPaths();
    if (!shouldContinue()) {
      return;
    }
    await this.artworkCache.cleanupTempFiles(shouldContinue);
    if (!shouldContinue()) {
      return;
    }
    await this.artworkCache.cleanupOrphans(referencedPaths, shouldContinue);
  }

  private scheduleArtworkCleanup(): void {
    const operation = this.artworkCleanupTail.then(async (): Promise<void> => {
      if (!this.importing && this.activeArtworkSession === undefined) {
        await this.cleanupArtworkFiles();
      }
    });
    this.artworkCleanupTail = operation.catch((error: Object): void => {
      console.warn(`Artwork orphan cleanup failed: ${MediaImporter.errorMessage(error)}`);
    });
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
      artworkTotal: progress.artworkTotal,
      artworkProcessed: progress.artworkProcessed,
      artworkSkipped: progress.artworkSkipped,
      artworkFailed: progress.artworkFailed,
      metadataCompleted: progress.metadataCompleted,
      cancelled: progress.cancelled,
      currentName: progress.currentName
    });
  }

  private async notifyLibraryChanged(callback: ImportLibraryChangedCallback | undefined,
    phase: ImportRefreshPhase): Promise<void> {
    if (callback === undefined) {
      return;
    }
    const startedAt = Date.now();
    try {
      await callback(phase);
      ImportPerformanceTrace.mark(`library_refresh_${phase}`, startedAt);
    } catch (error) {
      console.warn(`Library ${phase} refresh failed: ${MediaImporter.errorMessage(error)}`);
    }
  }

  private notifyFileCheck(callback: FileCheckProgressCallback | undefined,
    progress: FileCheckProgress): void {
    callback?.({
      total: progress.total,
      processed: progress.processed,
      updated: progress.updated,
      unavailable: progress.unavailable,
      recovered: progress.recovered,
      artworkRebuilt: progress.artworkRebuilt,
      artworkTotal: progress.artworkTotal,
      artworkProcessed: progress.artworkProcessed,
      artworkSkipped: progress.artworkSkipped,
      artworkFailed: progress.artworkFailed,
      metadataCompleted: progress.metadataCompleted,
      cancelled: progress.cancelled,
      currentName: progress.currentName
    });
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

  private static artworkWorkResult(outcome: ArtworkWorkOutcome,
    sourceHasArtwork: boolean = false, errorMessage: string = ''): ArtworkWorkResult {
    return {
      outcome: outcome,
      sourceHasArtwork: sourceHasArtwork,
      errorMessage: errorMessage
    };
  }

  private static throwIfArtworkCancelled(cancellation?: ArtworkWorkCancellation): void {
    if (cancellation !== undefined && cancellation.isCancelled()) {
      throw new Error('Artwork operation cancelled');
    }
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
