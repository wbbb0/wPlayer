import { common } from '@kit.AbilityKit';
import { MusicRepository } from '../data/MusicRepository';
import { ImportRefreshPhase, MediaImporter } from '../importer/MediaImporter';
import { ArtworkCache } from '../artwork/ArtworkCache';
import {
  AlbumListItem,
  AlbumDetail,
  AlbumSortField,
  ArtistReference,
  ArtistDetail,
  FileCheckProgress,
  FileCheckResult,
  FileCheckItemResult,
  ImportProgress,
  ImportResult,
  ImportItemDetailKind,
  ImportItemResult,
  LibraryStatistics,
  LibraryIndexPresentation,
  LibrarySection,
  SortDirection,
  TrackListItem,
  TrackNavigationTargets,
  TrackSortField,
  UnavailableTrackItem
} from '../model/LibraryModels';
import { SettingsRepository } from '../../settings/SettingsRepository';
import { appSettings } from '../../settings/AppSettingsStore';
import { LibraryListDataSource } from './LibraryListDataSource';
import { LibraryPlaybackBridge } from './LibraryPlaybackBridge';
import { ImportPerformanceTrace } from '../importer/ImportPerformanceTrace';
import { ImportDetailPolicy } from '../importer/ImportDetailPolicy';
import { ArtworkPaletteUpdate, PaletteRefreshAsset } from '../data/MusicRepositoryTypes';
import { DemoLibraryMode } from '../../demo/DemoLibraryMode';
import { DemoMusicLibrary } from '../../demo/DemoMusicLibrary';
import {
  RepositoryInvalidation,
  RepositoryInvalidationListener,
  RepositoryProjection
} from '../data/RepositoryInvalidation';

const PALETTE_REFRESH_CONCURRENCY: number = 4;

class PaletteRefreshCursor {
  nextIndex: number = 0;
  failed: number = 0;
}

@Observed
export class LibraryStore {
  readonly trackDataSource: LibraryListDataSource<TrackListItem> =
    new LibraryListDataSource<TrackListItem>();
  readonly albumDataSource: LibraryListDataSource<AlbumListItem> =
    new LibraryListDataSource<AlbumListItem>();
  readonly uriDuplicateDataSource: LibraryListDataSource<ImportItemResult> =
    new LibraryListDataSource<ImportItemResult>();
  readonly contentDuplicateDataSource: LibraryListDataSource<ImportItemResult> =
    new LibraryListDataSource<ImportItemResult>();
  readonly batchDuplicateDataSource: LibraryListDataSource<ImportItemResult> =
    new LibraryListDataSource<ImportItemResult>();
  readonly failedImportDataSource: LibraryListDataSource<ImportItemResult> =
    new LibraryListDataSource<ImportItemResult>();
  trackSections: Array<LibrarySection> = [];
  albumSections: Array<LibrarySection> = [];
  trackIndexPresentation: LibraryIndexPresentation = LibraryIndexPresentation.ALPHABET;
  albumIndexPresentation: LibraryIndexPresentation = LibraryIndexPresentation.ALPHABET;
  trackSortField: TrackSortField = TrackSortField.TITLE;
  trackSortDirection: SortDirection = SortDirection.ASCENDING;
  albumSortField: AlbumSortField = AlbumSortField.TITLE;
  albumSortDirection: SortDirection = SortDirection.ASCENDING;
  statistics: LibraryStatistics = {
    trackCount: 0,
    albumCount: 0,
    artworkCount: 0,
    unavailableTrackCount: 0
  };
  fileCheckProgress: FileCheckProgress = {
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
  fileCheckItems: Array<FileCheckItemResult> = [];
  lastTaskWasFileCheck: boolean = false;
  unavailableTracks: Array<UnavailableTrackItem> = [];
  importProgress: ImportProgress = {
    total: 0,
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
    currentName: ''
  };
  initialized: boolean = false;
  loading: boolean = false;
  importing: boolean = false;
  checkingFiles: boolean = false;
  rebuildingSortIndexes: boolean = false;
  refreshingPalettes: boolean = false;
  paletteRefreshProcessed: number = 0;
  paletteRefreshTotal: number = 0;
  paletteRefreshResult: string = '';
  fileCheckResult: string = '';
  lastMessage: string = '';
  errorMessage: string = '';
  lastImportResult?: ImportResult;
  importDetailCount: number = 0;
  uriDuplicateCount: number = 0;
  contentDuplicateCount: number = 0;
  batchDuplicateCount: number = 0;
  failedImportCount: number = 0;
  sortIndexResult: string = '';
  sortIndexError: string = '';
  private readonly repository: MusicRepository;
  private readonly playbackBridge?: LibraryPlaybackBridge;
  private importer?: MediaImporter;
  private artworkCache?: ArtworkCache;
  private settings?: SettingsRepository;
  private initializePromise?: Promise<void>;
  private refreshGeneration: number = 0;
  private trackSortGeneration: number = 0;
  private albumSortGeneration: number = 0;
  private observingInvalidations: boolean = false;
  private active: boolean = false;
  private needsActivationRefresh: boolean = false;
  private lastSeenInvalidationRevision: number = 0;
  private pendingLibraryRefresh: boolean = false;
  private pendingUnavailableRefresh: boolean = false;
  private invalidationRefreshPromise?: Promise<void>;
  private readonly invalidationListener: RepositoryInvalidationListener =
    (invalidation: RepositoryInvalidation): void => {
      this.lastSeenInvalidationRevision = invalidation.revision;
      this.queueInvalidation(invalidation);
    };
  private readonly trackNavigationCache: Map<number, TrackNavigationTargets> =
    new Map<number, TrackNavigationTargets>();

  constructor(repository?: MusicRepository, playbackBridge?: LibraryPlaybackBridge) {
    this.repository = repository === undefined ? new MusicRepository() : repository;
    this.playbackBridge = playbackBridge;
  }

  async initialize(context: common.UIAbilityContext, settings?: SettingsRepository): Promise<void> {
    this.active = true;
    if (this.initialized) {
      await this.reactivateIfNeeded();
      return;
    }
    if (this.initializePromise !== undefined) {
      await this.initializePromise;
      await this.reactivateIfNeeded();
      return;
    }
    this.initializePromise = this.initializeInternal(context, settings);
    try {
      await this.initializePromise;
    } finally {
      this.initializePromise = undefined;
    }
  }

  private async initializeInternal(context: common.UIAbilityContext,
    settings?: SettingsRepository): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      this.settings = settings === undefined ? new SettingsRepository(context) : settings;
      this.restoreSortSettings();
      this.artworkCache = new ArtworkCache(context);
      const databaseRebuilt = await this.repository.initialize(context);
      if (databaseRebuilt) {
        this.artworkCache.clearAll();
      }
      this.importer = new MediaImporter(context, this.repository, this.artworkCache);
      await this.importer.cleanupArtworkStorage();
      this.lastSeenInvalidationRevision = this.repository.currentInvalidationRevision();
      await this.refresh();
      this.initialized = true;
      if (this.active && !this.needsActivationRefresh) {
        await this.startObservingInvalidations();
      }
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.loading = false;
    }
  }

  async refresh(): Promise<void> {
    this.trackNavigationCache.clear();
    const refreshGeneration = ++this.refreshGeneration;
    const trackGeneration = ++this.trackSortGeneration;
    const albumGeneration = ++this.albumSortGeneration;
    const trackField = this.trackSortField;
    const trackDirection = this.trackSortDirection;
    const albumField = this.albumSortField;
    const albumDirection = this.albumSortDirection;
    const snapshots = await Promise.all([
      this.repository.getTracks(trackField, trackDirection),
      this.repository.getAlbums(albumField, albumDirection),
      this.repository.getStatistics()
    ]);
    if (refreshGeneration !== this.refreshGeneration || trackGeneration !== this.trackSortGeneration ||
      albumGeneration !== this.albumSortGeneration) {
      return;
    }
    const trackSnapshot = snapshots[0];
    const albumSnapshot = snapshots[1];
    this.trackDataSource.replace(trackSnapshot.items);
    this.trackSections = trackSnapshot.sections;
    this.trackIndexPresentation = trackSnapshot.indexPresentation;
    this.albumDataSource.replace(albumSnapshot.items);
    this.albumSections = albumSnapshot.sections;
    this.albumIndexPresentation = albumSnapshot.indexPresentation;
    this.statistics = snapshots[2];
  }

  async setTrackSort(field: TrackSortField, direction: SortDirection): Promise<void> {
    ++this.refreshGeneration;
    const generation = ++this.trackSortGeneration;
    this.trackSortField = field;
    this.trackSortDirection = direction;
    if (appSettings.rememberLibrarySort) {
      this.settings?.setSongSort(field, direction === SortDirection.DESCENDING);
    }
    try {
      const snapshot = await this.repository.getTracks(field, direction);
      if (generation === this.trackSortGeneration) {
        this.trackDataSource.replace(snapshot.items);
        this.trackSections = snapshot.sections;
        this.trackIndexPresentation = snapshot.indexPresentation;
      }
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    }
  }

  async setAlbumSort(field: AlbumSortField, direction: SortDirection): Promise<void> {
    ++this.refreshGeneration;
    const generation = ++this.albumSortGeneration;
    this.albumSortField = field;
    this.albumSortDirection = direction;
    if (appSettings.rememberLibrarySort) {
      this.settings?.setAlbumSort(field, direction === SortDirection.DESCENDING);
    }
    try {
      const snapshot = await this.repository.getAlbums(field, direction);
      if (generation === this.albumSortGeneration) {
        this.albumDataSource.replace(snapshot.items);
        this.albumSections = snapshot.sections;
        this.albumIndexPresentation = snapshot.indexPresentation;
      }
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    }
  }

  async selectAndImport(onStarted?: () => void): Promise<void> {
    if (DemoLibraryMode.isEnabled()) {
      this.lastMessage = '请先关闭演示音乐库，再导入本地音乐';
      return;
    }
    if (this.importer === undefined || this.importing) {
      return;
    }
    this.importing = true;
    this.lastTaskWasFileCheck = false;
    this.fileCheckResult = '';
    this.fileCheckItems = [];
    this.errorMessage = '';
    this.lastMessage = '';
    this.lastImportResult = undefined;
    this.clearImportDetails();
    try {
      const result = await this.importer.selectAndImport((progress: ImportProgress) => {
        this.importProgress = progress;
      }, onStarted, undefined, async (phase: ImportRefreshPhase): Promise<void> => {
        await this.synchronizeCommittedChanges();
        ImportPerformanceTrace.event('library_refresh_completed', 0, `phase=${phase}`);
      });
      this.lastImportResult = result;
      this.replaceImportDetails(result.items);
      this.lastMessage = LibraryStore.importSummary(result);
      if (result.imported <= 0) {
        ImportPerformanceTrace.event('post_import_refresh_skipped', 0, 'reason=no_library_changes');
      }
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.importing = false;
    }
  }

  cancelImport(): void {
    this.importer?.cancel();
  }

  private clearImportDetails(): void {
    this.importDetailCount = 0;
    this.uriDuplicateCount = 0;
    this.contentDuplicateCount = 0;
    this.batchDuplicateCount = 0;
    this.failedImportCount = 0;
    this.uriDuplicateDataSource.clear();
    this.contentDuplicateDataSource.clear();
    this.batchDuplicateDataSource.clear();
    this.failedImportDataSource.clear();
  }

  private replaceImportDetails(items: Array<ImportItemResult>): void {
    const uriDuplicates: Array<ImportItemResult> = [];
    const contentDuplicates: Array<ImportItemResult> = [];
    const batchDuplicates: Array<ImportItemResult> = [];
    const failures: Array<ImportItemResult> = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      switch (ImportDetailPolicy.kindOf(item)) {
        case ImportItemDetailKind.URI_DUPLICATE:
          uriDuplicates.push(item);
          break;
        case ImportItemDetailKind.CONTENT_DUPLICATE:
          contentDuplicates.push(item);
          break;
        case ImportItemDetailKind.BATCH_DUPLICATE:
          batchDuplicates.push(item);
          break;
        case ImportItemDetailKind.FAILED:
          failures.push(item);
          break;
        default:
          break;
      }
    }
    this.uriDuplicateCount = uriDuplicates.length;
    this.contentDuplicateCount = contentDuplicates.length;
    this.batchDuplicateCount = batchDuplicates.length;
    this.failedImportCount = failures.length;
    this.importDetailCount = this.uriDuplicateCount + this.contentDuplicateCount +
      this.batchDuplicateCount + this.failedImportCount;
    this.uriDuplicateDataSource.replace(uriDuplicates);
    this.contentDuplicateDataSource.replace(contentDuplicates);
    this.batchDuplicateDataSource.replace(batchDuplicates);
    this.failedImportDataSource.replace(failures);
  }

  async clearLibrary(): Promise<void> {
    if (this.importer === undefined || this.importing) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    try {
      await this.playbackBridge?.prepareForLibraryClear();
      await this.importer.clearLibrary();
      await this.synchronizeCommittedChanges();
      this.lastMessage = '音乐库已清空，原始音乐文件没有被删除';
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.loading = false;
    }
  }

  dispose(): void {
    this.active = false;
    this.needsActivationRefresh = true;
    ++this.refreshGeneration;
    ++this.trackSortGeneration;
    ++this.albumSortGeneration;
    this.pendingLibraryRefresh = false;
    this.pendingUnavailableRefresh = false;
    if (this.observingInvalidations) {
      this.repository.removeInvalidationListener(this.invalidationListener);
      this.observingInvalidations = false;
    }
  }

  private startObservingInvalidations(): Promise<void> {
    if (!this.active) {
      return Promise.resolve();
    }
    if (!this.observingInvalidations) {
      this.attachInvalidationListener();
      const currentRevision = this.repository.currentInvalidationRevision();
      if (currentRevision > this.lastSeenInvalidationRevision) {
        this.lastSeenInvalidationRevision = currentRevision;
        this.pendingLibraryRefresh = true;
        this.pendingUnavailableRefresh = true;
        return this.synchronizeInvalidations();
      }
    }
    return Promise.resolve();
  }

  private attachInvalidationListener(): void {
    if (!this.observingInvalidations) {
      this.repository.addInvalidationListener(this.invalidationListener);
      this.observingInvalidations = true;
    }
  }

  private async reactivateIfNeeded(): Promise<void> {
    if (!this.active || !this.initialized) {
      return;
    }
    if (this.needsActivationRefresh) {
      const baselineRevision = this.repository.currentInvalidationRevision();
      try {
        await this.refresh();
        await this.loadUnavailableTracks();
      } catch (error) {
        if (this.active) {
          this.pendingLibraryRefresh = true;
          this.pendingUnavailableRefresh = true;
          this.attachInvalidationListener();
        }
        throw new Error(LibraryStore.errorMessageOf(error));
      }
      if (!this.active) {
        return;
      }
      this.lastSeenInvalidationRevision = baselineRevision;
      this.needsActivationRefresh = false;
    }
    await this.startObservingInvalidations();
  }

  private queueInvalidation(invalidation: RepositoryInvalidation): void {
    if (!this.active || !this.initialized) {
      return;
    }
    if (invalidation.hasProjection(RepositoryProjection.LIBRARY_SUMMARY) ||
      invalidation.hasProjection(RepositoryProjection.LIBRARY_TRACKS) ||
      invalidation.hasProjection(RepositoryProjection.LIBRARY_ALBUMS)) {
      this.pendingLibraryRefresh = true;
    }
    if (invalidation.hasProjection(RepositoryProjection.UNAVAILABLE_TRACKS)) {
      this.pendingUnavailableRefresh = true;
    }
    if (!this.pendingLibraryRefresh && !this.pendingUnavailableRefresh) {
      return;
    }
    this.synchronizeInvalidations().catch((error: Object): void => {
      console.warn(`Unable to refresh invalidated library data: ${LibraryStore.errorMessageOf(error)}`);
    });
  }

  private synchronizeInvalidations(): Promise<void> {
    if (this.invalidationRefreshPromise !== undefined) {
      return this.invalidationRefreshPromise;
    }
    const running = this.drainInvalidations();
    this.invalidationRefreshPromise = running;
    const completeSuccess = (): void => {
      if (this.invalidationRefreshPromise === running) {
        this.invalidationRefreshPromise = undefined;
      }
      if (this.pendingLibraryRefresh || this.pendingUnavailableRefresh) {
        this.synchronizeInvalidations().catch((error: Object): void => {
          console.warn(`Unable to continue invalidated library refresh: ${LibraryStore.errorMessageOf(error)}`);
        });
      }
    };
    const completeFailure = (): void => {
      if (this.invalidationRefreshPromise === running) {
        this.invalidationRefreshPromise = undefined;
      }
    };
    running.then(completeSuccess, completeFailure);
    return running;
  }

  private async synchronizeCommittedChanges(): Promise<void> {
    try {
      await this.synchronizeInvalidations();
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
      console.warn(`Library change committed but projection refresh is pending: ${this.errorMessage}`);
    }
  }

  private async drainInvalidations(): Promise<void> {
    while (this.pendingLibraryRefresh || this.pendingUnavailableRefresh) {
      const refreshLibrary = this.pendingLibraryRefresh;
      const refreshUnavailable = this.pendingUnavailableRefresh;
      this.pendingLibraryRefresh = false;
      this.pendingUnavailableRefresh = false;
      try {
        if (refreshLibrary) {
          await this.refresh();
        }
        if (refreshUnavailable) {
          await this.loadUnavailableTracks();
        }
      } catch (error) {
        if (this.active) {
          this.pendingLibraryRefresh = this.pendingLibraryRefresh || refreshLibrary;
          this.pendingUnavailableRefresh = this.pendingUnavailableRefresh || refreshUnavailable;
        }
        throw new Error(LibraryStore.errorMessageOf(error));
      }
    }
  }

  async checkMusicFiles(): Promise<void> {
    if (this.importer === undefined || this.importing || this.loading || this.checkingFiles) {
      return;
    }
    this.checkingFiles = true;
    this.lastTaskWasFileCheck = true;
    this.errorMessage = '';
    this.fileCheckResult = '';
    this.fileCheckItems = [];
    try {
      const result: FileCheckResult = await this.importer.checkLibrary(
        (progress: FileCheckProgress): void => {
          this.fileCheckProgress = progress;
        },
        async (_phase: ImportRefreshPhase): Promise<void> => {
          await this.synchronizeCommittedChanges();
        }
      );
      this.fileCheckItems = result.items;
      this.fileCheckResult = `已检查 ${result.checked} 首，更新 ${result.updated} 首，` +
        `恢复 ${result.recovered} 首，重建封面 ${result.artworkRebuilt} 首，` +
        `封面失败 ${result.artworkFailed} 首，失效 ${this.statistics.unavailableTrackCount} 首` +
        (result.artworkSkipped > 0 ? `，取消时跳过封面 ${result.artworkSkipped} 个` : '');
      this.lastMessage = this.fileCheckResult;
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.checkingFiles = false;
    }
  }

  cancelFileCheck(): void {
    this.importer?.cancel();
  }

  async loadUnavailableTracks(): Promise<void> {
    const tracks = await this.repository.getUnavailableTracks();
    if (this.active) {
      this.unavailableTracks = tracks;
    }
  }

  async removeUnavailableTracks(trackIds: Array<number>): Promise<void> {
    if (trackIds.length === 0 || this.loading || this.importing || this.checkingFiles) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    try {
      await this.playbackBridge?.prepareForTrackRemoval(trackIds);
      const removed = await this.repository.removeTracks(trackIds);
      await this.synchronizeCommittedChanges();
      this.lastMessage = `已从音乐库移除 ${removed} 首失效文件记录`;
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.loading = false;
    }
  }

  clearAllUnavailableTracks(): Promise<void> {
    return this.removeUnavailableTracks(
      this.unavailableTracks.map((item: UnavailableTrackItem): number => item.trackId)
    );
  }

  async rebuildSortIndexes(): Promise<void> {
    if (this.importing || this.loading || this.rebuildingSortIndexes) {
      return;
    }
    this.rebuildingSortIndexes = true;
    this.errorMessage = '';
    this.lastMessage = '';
    this.sortIndexResult = '';
    this.sortIndexError = '';
    try {
      await this.repository.rebuildSortIndexes();
      await this.synchronizeCommittedChanges();
      this.lastMessage = '排序索引已根据音乐库元数据重建';
      this.sortIndexResult = this.lastMessage;
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
      this.sortIndexError = this.errorMessage;
    } finally {
      this.rebuildingSortIndexes = false;
    }
  }

  async refreshArtworkPalettes(): Promise<void> {
    if (this.importing || this.loading || this.rebuildingSortIndexes || this.refreshingPalettes ||
      this.artworkCache === undefined) {
      return;
    }
    this.refreshingPalettes = true;
    this.paletteRefreshProcessed = 0;
    this.paletteRefreshTotal = 0;
    this.paletteRefreshResult = '';
    this.errorMessage = '';
    this.lastMessage = '';
    try {
      const assets = await this.repository.getPaletteRefreshAssets();
      this.paletteRefreshTotal = assets.length;
      const updates: Array<ArtworkPaletteUpdate> = [];
      const cursor = new PaletteRefreshCursor();
      const workers: Array<Promise<void>> = [];
      const workerCount = Math.min(PALETTE_REFRESH_CONCURRENCY, assets.length);
      for (let index = 0; index < workerCount; index += 1) {
        workers.push(this.runPaletteRefreshWorker(assets, updates, cursor));
      }
      await Promise.all(workers);
      if (updates.length > 0) {
        await this.repository.updateArtworkPalettes(updates);
        await this.playbackBridge?.refreshCurrentTrackPalette();
      }
      await this.synchronizeCommittedChanges();
      this.paletteRefreshResult = `已刷新 ${updates.length} 张封面` +
        (cursor.failed > 0 ? `，失败 ${cursor.failed} 张` : '');
      this.lastMessage = this.paletteRefreshResult;
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.refreshingPalettes = false;
    }
  }

  private async runPaletteRefreshWorker(assets: Array<PaletteRefreshAsset>,
    updates: Array<ArtworkPaletteUpdate>, cursor: PaletteRefreshCursor): Promise<void> {
    while (cursor.nextIndex < assets.length) {
      const index = cursor.nextIndex;
      cursor.nextIndex += 1;
      const asset = assets[index];
      try {
        if (this.artworkCache === undefined) {
          return;
        }
        const palette = await this.artworkCache.extractPalette(asset.artworkPath);
        updates.push({ id: asset.id, palette: palette });
      } catch (error) {
        cursor.failed += 1;
        console.warn(`Palette refresh failed for artwork ${asset.id}: ${LibraryStore.errorMessageOf(error)}`);
      }
      this.paletteRefreshProcessed += 1;
    }
  }

  resolveArtworkPath(relativePath: string): string {
    if (DemoMusicLibrary.isArtworkPath(relativePath)) {
      return relativePath;
    }
    if (relativePath.length === 0 || this.artworkCache === undefined) {
      return '';
    }
    return `file://${this.artworkCache.resolvePath(relativePath)}`;
  }

  async loadTrackSnapshot(): Promise<Array<TrackListItem>> {
    return this.trackDataSource.snapshot();
  }

  getAlbumDetail(albumId: number): Promise<AlbumDetail | undefined> {
    return this.repository.getAlbumDetail(albumId);
  }

  getAlbumArtists(albumId: number): Promise<Array<ArtistReference>> {
    return this.repository.getAlbumArtists(albumId);
  }

  getArtistDetail(artistId: number): Promise<ArtistDetail | undefined> {
    return this.repository.getArtistDetail(artistId);
  }

  async getTrackNavigationTargets(trackId: number): Promise<TrackNavigationTargets | undefined> {
    const cached = this.trackNavigationCache.get(trackId);
    if (cached !== undefined) {
      return cached;
    }
    const targets = await this.repository.getTrackNavigationTargets(trackId);
    if (targets !== undefined) {
      this.trackNavigationCache.set(trackId, targets);
    }
    return targets;
  }

  setRememberSort(value: boolean): void {
    appSettings.setRememberLibrarySort(value);
    if (value) {
      this.settings?.setSongSort(
        this.trackSortField,
        this.trackSortDirection === SortDirection.DESCENDING
      );
      this.settings?.setAlbumSort(
        this.albumSortField,
        this.albumSortDirection === SortDirection.DESCENDING
      );
    }
  }

  private restoreSortSettings(): void {
    if (this.settings === undefined) {
      return;
    }
    if (!appSettings.rememberLibrarySort) {
      this.trackSortField = TrackSortField.TITLE;
      this.trackSortDirection = SortDirection.ASCENDING;
      this.albumSortField = AlbumSortField.TITLE;
      this.albumSortDirection = SortDirection.ASCENDING;
      return;
    }
    const trackField = this.settings.getSongSortField(TrackSortField.TITLE);
    this.trackSortField = trackField >= TrackSortField.TITLE && trackField <= TrackSortField.ADDED_AT ?
      trackField as TrackSortField : TrackSortField.TITLE;
    this.trackSortDirection = this.settings.getSongSortDescending() ?
      SortDirection.DESCENDING : SortDirection.ASCENDING;
    const albumField = this.settings.getAlbumSortField(AlbumSortField.TITLE);
    this.albumSortField = albumField >= AlbumSortField.TITLE && albumField <= AlbumSortField.ADDED_AT ?
      albumField as AlbumSortField : AlbumSortField.TITLE;
    this.albumSortDirection = this.settings.getAlbumSortDescending() ?
      SortDirection.DESCENDING : SortDirection.ASCENDING;
  }

  private static importSummary(result: ImportResult): string {
    if (result.imported === 0 && result.duplicates === 0 && result.failed === 0) {
      return '';
    }
    const skippedArtwork = result.artworkSkipped > 0 ?
      `，取消时跳过封面 ${result.artworkSkipped} 个` : '';
    return `已导入 ${result.imported} 首，重复 ${result.duplicates} 首，` +
      `失败 ${result.failed} 首，封面失败 ${result.artworkFailed} 个${skippedArtwork}`;
  }

  private static errorMessageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
