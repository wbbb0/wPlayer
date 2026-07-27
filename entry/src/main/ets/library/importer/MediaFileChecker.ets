import { ArtworkCache } from '../artwork/ArtworkCache';
import { ArtworkRepairPolicy } from '../artwork/ArtworkRepairPolicy';
import {
  ArtworkWorkOutcome,
  ArtworkWorkRequest,
  ArtworkWorkResult,
  ArtworkWorkSession
} from '../artwork/ArtworkWorkSession';
import { ArtworkImportInput, MusicRepository } from '../data/MusicRepository';
import { RepositoryContentChangeKind } from '../data/RepositoryInvalidation';
import { MetadataReader } from '../metadata/MetadataReader';
import {
  inspectMediaFiles,
  MediaFileInspectionInput,
  MediaFileInspectionResult
} from '../metadata/MediaFileTasks';
import {
  ArtworkState,
  AvailabilityState,
  FileCheckItemOutcome,
  FileCheckItemResult,
  FileCheckProgress,
  FileCheckResult,
  MediaFileCheckCandidate,
  ParsedArtwork,
  TrackAvailabilityUpdate
} from '../model/LibraryModels';
import {
  ensureReadPermissions,
  ReadPermissionBatchResult,
  ReadPermissionProgress
} from './MediaPickerService';
import { ImportConcurrencyPolicy } from './ImportConcurrencyPolicy';
import {
  FileCheckProgressCallback,
  ImportLibraryChangedCallback,
  ImportRefreshPhase
} from './MediaImportCallbacks';
import { MediaArtworkPipeline } from './MediaArtworkPipeline';
import { MediaImportOperation } from './MediaImportOperation';

interface ProgressNotificationGate {
  lastAt: number;
  intervalMs: number;
}

interface FileCheckWorkResult {
  updated: boolean;
  unavailable: boolean;
  recovered: boolean;
  artworkRebuilt: boolean;
  item?: FileCheckItemResult;
  availabilityUpdate?: TrackAvailabilityUpdate;
  artworkRequest?: ArtworkWorkRequest;
  artworkItem?: FileCheckItemResult;
}

interface PendingArtworkWork {
  request: ArtworkWorkRequest;
  item?: FileCheckItemResult;
}

type FileCheckArtworkScheduler = (work: PendingArtworkWork) => Promise<void>;

export class MediaFileChecker {
  private readonly repository: MusicRepository;
  private readonly artworkCache: ArtworkCache;
  private readonly artworkPipeline: MediaArtworkPipeline;
  private readonly operation: MediaImportOperation;

  constructor(repository: MusicRepository, artworkCache: ArtworkCache,
    artworkPipeline: MediaArtworkPipeline, operation: MediaImportOperation) {
    this.repository = repository;
    this.artworkCache = artworkCache;
    this.artworkPipeline = artworkPipeline;
    this.operation = operation;
  }

  private get cancelRequested(): boolean {
    return this.operation.isCancelled();
  }

  async checkLibrary(onProgress?: FileCheckProgressCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<FileCheckResult> {
    this.artworkPipeline.clearOperationContext();
    const artworkSession = this.createArtworkSession();
    const progress: FileCheckProgress = {
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
      if (this.cancelRequested) {
        progress.cancelled = true;
      }
      progress.total = candidates.length;
      const progressGate: ProgressNotificationGate = {
        lastAt: 0,
        intervalMs: ImportConcurrencyPolicy.IMPORT_PROGRESS_INTERVAL_MS
      };
      this.notifyFileCheck(onProgress, progress, progressGate, true);
      const startedAt = Date.now();
      const availabilityUpdates: Array<TrackAvailabilityUpdate> = [];
      const itemResults: Array<FileCheckItemResult> = [];
      const candidateBuckets = MediaFileChecker.createCandidateBuckets(candidates);
      const handledPermissionUris: Set<string> = new Set<string>();
      const scanSlots: Array<Promise<void> | undefined> =
        new Array<Promise<void> | undefined>(
          ImportConcurrencyPolicy.FILE_CHECK_PIPELINE_CONCURRENCY
        );
      const artworkSlots: Array<Promise<void> | undefined> =
        new Array<Promise<void> | undefined>(
          ImportConcurrencyPolicy.FILE_CHECK_ARTWORK_QUEUE_CAPACITY
        );
      let nextScanSlot = 0;
      let nextArtworkSlot = 0;
      let lastArtworkProgressAt = 0;

      artworkSession.startProcessing();
      const scheduleArtwork = async (work: PendingArtworkWork): Promise<void> => {
        if (this.cancelRequested) {
          return;
        }
        const slot = nextArtworkSlot;
        nextArtworkSlot = (nextArtworkSlot + 1) % artworkSlots.length;
        const previous = artworkSlots[slot];
        if (previous !== undefined) {
          await previous;
        }
        if (this.cancelRequested) {
          return;
        }
        progress.artworkTotal += 1;
        const operation = artworkSession.enqueue(work.request).then(
          (result: ArtworkWorkResult): void => {
            this.applyFileCheckArtworkResult(work, result, progress, itemResults);
            const now = Date.now();
            if (now - lastArtworkProgressAt >=
              ImportConcurrencyPolicy.IMPORT_PROGRESS_INTERVAL_MS ||
              progress.artworkProcessed >= progress.artworkTotal) {
              lastArtworkProgressAt = now;
              this.notifyFileCheck(onProgress, progress, progressGate, true);
            }
          }
        );
        artworkSlots[slot] = operation;
      };

      progress.currentName = '正在激活文件访问权限';
      this.notifyFileCheck(onProgress, progress, progressGate, true);
      const permissionStartedAt = Date.now();
      const permissions = await ensureReadPermissions(
        candidates.map((candidate: MediaFileCheckCandidate): string => candidate.uri),
        (permissionProgress: ReadPermissionProgress): void => {
          progress.currentName = `正在并行检查音乐文件 · 权限 ` +
            `${permissionProgress.processed} / ${permissionProgress.total}`;
          if (this.notifyFileCheck(
            onProgress, progress, progressGate,
            permissionProgress.processed >= permissionProgress.total
          )) {
            console.info(`[FileCheck] permission batch ${permissionProgress.processed}/` +
              `${permissionProgress.total} in ${permissionProgress.batchDurationMs}ms`);
          }
        },
        {
          shouldContinue: (): boolean => !this.cancelRequested,
          onBatch: async (batchResult: ReadPermissionBatchResult): Promise<void> => {
            this.recordPermissionFailures(
              batchResult.failedUris,
              candidateBuckets,
              handledPermissionUris,
              availabilityUpdates,
              itemResults,
              progress
            );
            const accessibleCandidates = MediaFileChecker.takePermissionCandidates(
              batchResult.successfulUris,
              candidateBuckets,
              handledPermissionUris
            );
            for (let offset = 0; offset < accessibleCandidates.length;
              offset += ImportConcurrencyPolicy.FILE_CHECK_BATCH_SIZE) {
              if (this.cancelRequested) {
                break;
              }
              const slot = nextScanSlot;
              nextScanSlot = (nextScanSlot + 1) % scanSlots.length;
              const previous = scanSlots[slot];
              if (previous !== undefined) {
                await previous;
              }
              if (this.cancelRequested) {
                break;
              }
              const scanBatch = accessibleCandidates.slice(
                offset,
                Math.min(
                  offset + ImportConcurrencyPolicy.FILE_CHECK_BATCH_SIZE,
                  accessibleCandidates.length
                )
              );
              scanSlots[slot] = this.processFileCheckBatch(
                scanBatch,
                progress,
                availabilityUpdates,
                itemResults,
                scheduleArtwork,
                onProgress,
                progressGate
              );
            }
          }
        }
      );
      this.recordPermissionFailures(
        permissions.failedUris,
        candidateBuckets,
        handledPermissionUris,
        availabilityUpdates,
        itemResults,
        progress
      );
      console.info(`[FileCheck] permissions ${Date.now() - permissionStartedAt}ms, ` +
        `available=${permissions.successfulUris.length}, failed=${permissions.failedUris.length}, ` +
        `cancelled=${permissions.cancelled}`);
      progress.currentName = this.cancelRequested ?
        '正在停止音乐文件检查' : '正在等待文件检查队列';
      this.notifyFileCheck(onProgress, progress, progressGate, true);
      for (let index = 0; index < scanSlots.length; index += 1) {
        const operation = scanSlots[index];
        if (operation !== undefined) {
          await operation;
        }
      }
      progress.currentName = '正在保存检查结果';
      this.notifyFileCheck(onProgress, progress, progressGate, true);
      if (!this.cancelRequested) {
        await this.repository.setTrackAvailabilities(availabilityUpdates);
      }
      const artworkWasScheduled = progress.artworkTotal > 0;
      progress.metadataCompleted = true;
      progress.cancelled = this.cancelRequested || permissions.cancelled;
      progress.currentName = artworkWasScheduled && !progress.cancelled ?
        '正在处理封面' : (progress.cancelled ? '音乐文件检查已停止' : '');
      this.notifyFileCheck(onProgress, progress, progressGate, true);
      if (availabilityUpdates.length > 0 || progress.updated > 0) {
        await this.notifyLibraryChanged(onLibraryChanged, ImportRefreshPhase.METADATA);
      }
      for (let index = 0; index < artworkSlots.length; index += 1) {
        const operation = artworkSlots[index];
        if (operation !== undefined) {
          await operation;
        }
      }
      await artworkSession.waitForIdle();
      progress.cancelled = progress.cancelled || this.cancelRequested ||
        artworkSession.isCancelled();
      if (artworkWasScheduled) {
        await this.notifyLibraryChanged(onLibraryChanged, ImportRefreshPhase.ARTWORK);
      }
      progress.currentName = '';
      this.notifyFileCheck(onProgress, progress, progressGate, true);
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
      await this.operation.cancelAndWait();
      this.artworkPipeline.scheduleCleanup();
    }
  }

  private async processFileCheckBatch(candidates: Array<MediaFileCheckCandidate>,
    progress: FileCheckProgress,
    availabilityUpdates: Array<TrackAvailabilityUpdate>,
    itemResults: Array<FileCheckItemResult>,
    scheduleArtwork: FileCheckArtworkScheduler,
    onProgress?: FileCheckProgressCallback,
    progressGate?: ProgressNotificationGate): Promise<void> {
    if (candidates.length === 0 || this.cancelRequested) {
      return;
    }
    const startedAt = Date.now();
    const inspections = await inspectMediaFiles(this.createFileInspectionInputs(candidates));
    console.info(`[FileCheck] inspected pipeline batch ${candidates.length} in ` +
      `${Date.now() - startedAt}ms`);
    if (this.cancelRequested) {
      return;
    }
    for (let index = 0; index < candidates.length; index += 1) {
      if (this.cancelRequested) {
        break;
      }
      const outcome = await this.checkOneFile(candidates[index], inspections[index]);
      this.applyFileCheckOutcome(
        outcome, progress, availabilityUpdates, itemResults
      );
      if (outcome.artworkRequest !== undefined && !this.cancelRequested) {
        await scheduleArtwork({
          request: outcome.artworkRequest,
          item: outcome.artworkItem
        });
      }
      progress.processed += 1;
      progress.currentName = '正在并行检查音乐文件';
      this.notifyFileCheck(onProgress, progress, progressGate);
      if ((index + 1) % ImportConcurrencyPolicy.FILE_CHECK_CLASSIFY_CHUNK_SIZE === 0) {
        await MediaFileChecker.yieldToUi();
      }
    }
  }

  private applyFileCheckOutcome(outcome: FileCheckWorkResult,
    progress: FileCheckProgress,
    availabilityUpdates: Array<TrackAvailabilityUpdate>,
    itemResults: Array<FileCheckItemResult>): void {
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
    if (outcome.item !== undefined) {
      itemResults.push(outcome.item);
    }
    if (outcome.availabilityUpdate !== undefined) {
      availabilityUpdates.push(outcome.availabilityUpdate);
    }
  }

  private applyFileCheckArtworkResult(work: PendingArtworkWork,
    artworkResult: ArtworkWorkResult,
    progress: FileCheckProgress,
    itemResults: Array<FileCheckItemResult>): void {
    progress.artworkProcessed += 1;
    if (artworkResult.outcome === ArtworkWorkOutcome.COMPLETED) {
      if (artworkResult.sourceHasArtwork) {
        progress.artworkRebuilt += 1;
      }
      if (work.item !== undefined) {
        itemResults.push({
          trackId: work.item.trackId,
          displayName: work.item.displayName,
          uri: work.item.uri,
          outcome: artworkResult.sourceHasArtwork ?
            work.item.outcome : FileCheckItemOutcome.ARTWORK_ABSENT,
          reason: artworkResult.sourceHasArtwork ?
            work.item.reason : '已确认源文件没有封面'
        });
      }
    } else if (artworkResult.outcome === ArtworkWorkOutcome.SKIPPED) {
      progress.artworkSkipped += 1;
    } else if (artworkResult.outcome === ArtworkWorkOutcome.FAILED) {
      progress.artworkFailed += 1;
      if (work.item !== undefined) {
        itemResults.push({
          trackId: work.item.trackId,
          displayName: work.item.displayName,
          uri: work.item.uri,
          outcome: FileCheckItemOutcome.ARTWORK_FAILED,
          reason: artworkResult.errorMessage.length > 0 ?
            artworkResult.errorMessage : '封面处理失败'
        });
      }
    }
  }

  private recordPermissionFailures(uris: Array<string>,
    candidateBuckets: Map<string, Array<MediaFileCheckCandidate>>,
    handledUris: Set<string>,
    availabilityUpdates: Array<TrackAvailabilityUpdate>,
    itemResults: Array<FileCheckItemResult>,
    progress: FileCheckProgress): void {
    for (let index = 0; index < uris.length; index += 1) {
      const uri = uris[index];
      if (handledUris.has(uri)) {
        continue;
      }
      handledUris.add(uri);
      const candidates = candidateBuckets.get(uri) ?? [];
      for (let candidateIndex = 0; candidateIndex < candidates.length; candidateIndex += 1) {
        const candidate = candidates[candidateIndex];
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
    }
  }

  private static createCandidateBuckets(
    candidates: Array<MediaFileCheckCandidate>
  ): Map<string, Array<MediaFileCheckCandidate>> {
    const buckets: Map<string, Array<MediaFileCheckCandidate>> =
      new Map<string, Array<MediaFileCheckCandidate>>();
    for (let index = 0; index < candidates.length; index += 1) {
      const candidate = candidates[index];
      const bucket = buckets.get(candidate.uri);
      if (bucket === undefined) {
        buckets.set(candidate.uri, [candidate]);
      } else {
        bucket.push(candidate);
      }
    }
    return buckets;
  }

  private static takePermissionCandidates(uris: Array<string>,
    candidateBuckets: Map<string, Array<MediaFileCheckCandidate>>,
    handledUris: Set<string>): Array<MediaFileCheckCandidate> {
    const candidates: Array<MediaFileCheckCandidate> = [];
    for (let index = 0; index < uris.length; index += 1) {
      const uri = uris[index];
      if (handledUris.has(uri)) {
        continue;
      }
      handledUris.add(uri);
      const bucket = candidateBuckets.get(uri);
      if (bucket !== undefined) {
        candidates.push(...bucket);
      }
    }
    return candidates;
  }

  private async checkOneFile(candidate: MediaFileCheckCandidate,
    inspection: MediaFileInspectionResult): Promise<FileCheckWorkResult> {
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
        return this.repairArtwork(candidate);
      }
      let artworkRequest: ArtworkWorkRequest | undefined;
      let artworkItem: FileCheckItemResult | undefined;
      if (this.needsArtworkRepair(candidate, inspection.artworkFilesAvailable)) {
        const repairResult = this.repairArtwork(candidate);
        artworkRequest = repairResult.artworkRequest;
        artworkItem = repairResult.artworkItem;
      }
      return {
        updated: false,
        unavailable: false,
        recovered: true,
        artworkRebuilt: false,
        artworkRequest: artworkRequest,
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
      if (this.cancelRequested) {
        return { updated: false, unavailable: false, recovered: false, artworkRebuilt: false };
      }
      await this.repository.refreshTrack(candidate.trackId, {
        uri: candidate.uri,
        displayName: readResult.fileName,
        fileSize: readResult.fileSize,
        modifiedAt: readResult.modifiedAt,
        quickFingerprint: readResult.quickFingerprint,
        fullFingerprint: '',
        authorizationPersisted: true,
        metadata: readResult.metadata,
        artworks: MediaFileChecker.artworkMetadataOnly(readResult.metadata.artworks)
      });
      let artworkRequest: ArtworkWorkRequest | undefined;
      let artworkItem: FileCheckItemResult | undefined;
      if (readResult.metadata.artworks.length > 0) {
        artworkRequest = {
          trackId: candidate.trackId,
          uri: candidate.uri,
          fileSize: readResult.fileSize,
          modifiedAt: readResult.modifiedAt,
          metadata: readResult.metadata
        };
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
        artworkRequest: artworkRequest,
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
      console.warn(`Unable to refresh ${candidate.displayName}: ${MediaFileChecker.errorMessage(error)}`);
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


  private needsArtworkRepair(candidate: MediaFileCheckCandidate, filesAvailable: boolean): boolean {
    if (ArtworkRepairPolicy.needsRepair(
      candidate.artworkState, filesAvailable, filesAvailable,
      candidate.artworkAttemptCount, candidate.artworkLastAttemptAt
    )) {
      return true;
    }
    return candidate.artworkState === ArtworkState.READY && filesAvailable && (
      ArtworkRepairPolicy.hasSuspiciousLargeVariant(
        candidate.artworkSmallWidth, candidate.artworkSmallHeight, candidate.artworkSmallByteSize,
        candidate.artworkLargeWidth, candidate.artworkLargeHeight, candidate.artworkLargeByteSize
      ) ||
      ArtworkRepairPolicy.hasOutdatedVariantDimensions(
        candidate.artworkSourceWidth, candidate.artworkSourceHeight,
        candidate.artworkSmallWidth, candidate.artworkSmallHeight,
        candidate.artworkLargeWidth, candidate.artworkLargeHeight
      )
    );
  }

  private createFileInspectionInputs(
    candidates: Array<MediaFileCheckCandidate>
  ): Array<MediaFileInspectionInput> {
    return candidates.map((candidate: MediaFileCheckCandidate): MediaFileInspectionInput => {
      const checkArtworkFiles = candidate.artworkState === ArtworkState.READY &&
        candidate.artworkSmallPath.length > 0 && candidate.artworkLargePath.length > 0;
      return {
        uri: candidate.uri,
        artworkSmallPath: checkArtworkFiles ?
          this.artworkCache.resolvePath(candidate.artworkSmallPath) : '',
        artworkLargePath: checkArtworkFiles ?
          this.artworkCache.resolvePath(candidate.artworkLargePath) : ''
      };
    });
  }

  private repairArtwork(candidate: MediaFileCheckCandidate): FileCheckWorkResult {
    return {
      updated: false,
      unavailable: false,
      recovered: false,
      artworkRebuilt: false,
      artworkRequest: {
        trackId: candidate.trackId,
        uri: candidate.uri,
        fileSize: candidate.fileSize,
        modifiedAt: candidate.modifiedAt
      },
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
    return this.artworkPipeline.createSession(this.operation);
  }

  private notifyFileCheck(callback: FileCheckProgressCallback | undefined,
    progress: FileCheckProgress, gate?: ProgressNotificationGate,
    force: boolean = false): boolean {
    if (callback === undefined || !MediaFileChecker.shouldNotify(gate, force)) {
      return false;
    }
    callback({
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
      cancelled: progress.cancelled || this.cancelRequested,
      currentName: this.cancelRequested && !progress.metadataCompleted ?
        '正在停止音乐文件检查' : progress.currentName
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
    try {
      await callback(phase);
    } catch (error) {
      console.warn(`Library ${phase} refresh failed: ${MediaFileChecker.errorMessage(error)}`);
    }
  }

  private static artworkMetadataOnly(artworks: Array<ParsedArtwork>): Array<ArtworkImportInput> {
    return artworks.map((metadata: ParsedArtwork): ArtworkImportInput => {
      return { metadata: metadata };
    });
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

  private static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  private static yieldToUi(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
  }
}
