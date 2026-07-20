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
import { LibraryPageLoader, PagedLibraryDataSource } from './PagedLibraryDataSource';
import { LibraryPagingPolicy } from './LibraryPagingPolicy';
import { LibraryListDataSource } from './LibraryListDataSource';
import { LibraryPlaybackBridge } from './LibraryPlaybackBridge';
import { ImportPerformanceTrace } from '../importer/ImportPerformanceTrace';
import { ImportDetailPolicy } from '../importer/ImportDetailPolicy';
import { ArtworkPaletteUpdate, PaletteRefreshAsset } from '../data/MusicRepositoryTypes';

const PALETTE_REFRESH_CONCURRENCY: number = 4;

class TrackPageLoader implements LibraryPageLoader<TrackListItem> {
  private readonly repository: MusicRepository;
  private readonly field: TrackSortField;
  private readonly direction: SortDirection;

  constructor(repository: MusicRepository, field: TrackSortField, direction: SortDirection) {
    this.repository = repository;
    this.field = field;
    this.direction = direction;
  }

  async load(offset: number, limit: number): Promise<Array<TrackListItem>> {
    const page = await this.repository.getTrackPage(this.field, this.direction, offset, limit);
    return page.items;
  }
}

class AlbumPageLoader implements LibraryPageLoader<AlbumListItem> {
  private readonly repository: MusicRepository;
  private readonly field: AlbumSortField;
  private readonly direction: SortDirection;

  constructor(repository: MusicRepository, field: AlbumSortField, direction: SortDirection) {
    this.repository = repository;
    this.field = field;
    this.direction = direction;
  }

  async load(offset: number, limit: number): Promise<Array<AlbumListItem>> {
    const page = await this.repository.getAlbumPage(this.field, this.direction, offset, limit);
    return page.items;
  }
}

class PaletteRefreshCursor {
  nextIndex: number = 0;
  failed: number = 0;
}

@Observed
export class LibraryStore {
  readonly trackDataSource: PagedLibraryDataSource<TrackListItem> =
    new PagedLibraryDataSource<TrackListItem>(LibraryPagingPolicy.TRACK_PAGE_SIZE, 7);
  readonly albumDataSource: PagedLibraryDataSource<AlbumListItem> =
    new PagedLibraryDataSource<AlbumListItem>(LibraryPagingPolicy.ALBUM_PAGE_SIZE, 5);
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
  private readonly trackNavigationCache: Map<number, TrackNavigationTargets> =
    new Map<number, TrackNavigationTargets>();

  constructor(repository?: MusicRepository, playbackBridge?: LibraryPlaybackBridge) {
    this.repository = repository === undefined ? new MusicRepository() : repository;
    this.playbackBridge = playbackBridge;
    this.playbackBridge?.setLibraryMutationListener((): void => {
      if (this.initialized) {
        this.refresh().then((): Promise<void> => this.loadUnavailableTracks()).catch((error: Object): void => {
          console.warn(`Unable to refresh after playback library change: ${LibraryStore.errorMessageOf(error)}`);
        });
      }
    });
  }

  async initialize(context: common.UIAbilityContext, settings?: SettingsRepository): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (this.initializePromise !== undefined) {
      return this.initializePromise;
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
      await this.refresh();
      this.initialized = true;
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
      this.repository.getTrackCatalog(trackField, trackDirection),
      this.repository.getAlbumCatalog(albumField, albumDirection),
      this.repository.getStatistics()
    ]);
    if (refreshGeneration !== this.refreshGeneration || trackGeneration !== this.trackSortGeneration ||
      albumGeneration !== this.albumSortGeneration) {
      return;
    }
    const trackSnapshot = snapshots[0];
    const albumSnapshot = snapshots[1];
    this.trackDataSource.reset(trackSnapshot.totalCount,
      new TrackPageLoader(this.repository, trackField, trackDirection));
    this.trackSections = trackSnapshot.sections;
    this.trackIndexPresentation = trackSnapshot.indexPresentation;
    this.albumDataSource.reset(albumSnapshot.totalCount,
      new AlbumPageLoader(this.repository, albumField, albumDirection));
    this.albumSections = albumSnapshot.sections;
    this.albumIndexPresentation = albumSnapshot.indexPresentation;
    this.statistics = snapshots[2];
    await Promise.all([
      this.trackDataSource.ensureRange(0, LibraryPagingPolicy.TRACK_PAGE_SIZE - 1),
      this.albumDataSource.ensureRange(0, LibraryPagingPolicy.ALBUM_PAGE_SIZE - 1)
    ]);
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
      const snapshot = await this.repository.getTrackCatalog(field, direction);
      if (generation === this.trackSortGeneration) {
        this.trackDataSource.reset(snapshot.totalCount, new TrackPageLoader(this.repository, field, direction));
        this.trackSections = snapshot.sections;
        this.trackIndexPresentation = snapshot.indexPresentation;
        await this.trackDataSource.ensureRange(0, LibraryPagingPolicy.TRACK_PAGE_SIZE - 1);
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
      const snapshot = await this.repository.getAlbumCatalog(field, direction);
      if (generation === this.albumSortGeneration) {
        this.albumDataSource.reset(snapshot.totalCount, new AlbumPageLoader(this.repository, field, direction));
        this.albumSections = snapshot.sections;
        this.albumIndexPresentation = snapshot.indexPresentation;
        await this.albumDataSource.ensureRange(0, LibraryPagingPolicy.ALBUM_PAGE_SIZE - 1);
      }
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    }
  }

  async selectAndImport(onStarted?: () => void): Promise<void> {
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
        await this.refresh();
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
      this.lastMessage = '音乐库已清空，原始音乐文件没有被删除';
      await this.refresh();
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.loading = false;
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
          await this.refresh();
        }
      );
      await this.loadUnavailableTracks();
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
    this.unavailableTracks = await this.repository.getUnavailableTracks();
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
      await this.refresh();
      await this.loadUnavailableTracks();
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
      await this.refresh();
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
      await this.refresh();
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
    if (relativePath.length === 0 || this.artworkCache === undefined) {
      return '';
    }
    return `file://${this.artworkCache.resolvePath(relativePath)}`;
  }

  ensureTrackRange(firstIndex: number, lastIndex: number): void {
    this.trackDataSource.ensureRange(firstIndex, lastIndex).catch((_error: Object) => {
      // The data source keeps placeholders and retries on the next explicit visible-range request.
    });
  }

  ensureAlbumRange(firstIndex: number, lastIndex: number): void {
    this.albumDataSource.ensureRange(firstIndex, lastIndex).catch((_error: Object) => {
      // The data source keeps placeholders and retries on the next explicit visible-range request.
    });
  }

  async loadTrackSnapshot(): Promise<Array<TrackListItem>> {
    const snapshot = await this.repository.getTracks(this.trackSortField, this.trackSortDirection);
    return snapshot.items;
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
