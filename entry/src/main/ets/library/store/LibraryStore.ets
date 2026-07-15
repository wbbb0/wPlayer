import { common } from '@kit.AbilityKit';
import { MusicRepository } from '../data/MusicRepository';
import { MediaImporter } from '../importer/MediaImporter';
import { ArtworkCache } from '../artwork/ArtworkCache';
import {
  AlbumListItem,
  AlbumDetail,
  AlbumSortField,
  ImportProgress,
  ImportResult,
  ImportItemResult,
  ImportItemOutcome,
  LibraryStatistics,
  LibraryIndexPresentation,
  LibrarySection,
  SortDirection,
  TrackListItem,
  TrackSortField
} from '../model/LibraryModels';
import { SettingsRepository } from '../../settings/SettingsRepository';
import { LibraryListDataSource } from './LibraryListDataSource';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { ImportPerformanceTrace } from '../importer/ImportPerformanceTrace';

@Observed
export class LibraryStore {
  readonly trackDataSource: LibraryListDataSource<TrackListItem> = new LibraryListDataSource<TrackListItem>();
  readonly albumDataSource: LibraryListDataSource<AlbumListItem> = new LibraryListDataSource<AlbumListItem>();
  trackSections: Array<LibrarySection> = [];
  albumSections: Array<LibrarySection> = [];
  trackIndexPresentation: LibraryIndexPresentation = LibraryIndexPresentation.ALPHABET;
  albumIndexPresentation: LibraryIndexPresentation = LibraryIndexPresentation.ALPHABET;
  trackSortField: TrackSortField = TrackSortField.TITLE;
  trackSortDirection: SortDirection = SortDirection.ASCENDING;
  albumSortField: AlbumSortField = AlbumSortField.TITLE;
  albumSortDirection: SortDirection = SortDirection.ASCENDING;
  statistics: LibraryStatistics = { trackCount: 0, albumCount: 0, artworkCount: 0 };
  importProgress: ImportProgress = {
    total: 0,
    processed: 0,
    imported: 0,
    duplicates: 0,
    failed: 0,
    currentName: ''
  };
  initialized: boolean = false;
  loading: boolean = false;
  importing: boolean = false;
  rebuildingSortIndexes: boolean = false;
  lastMessage: string = '';
  errorMessage: string = '';
  lastImportResult?: ImportResult;
  importDetailItems: Array<ImportItemResult> = [];
  sortIndexResult: string = '';
  sortIndexError: string = '';
  albumDetail?: AlbumDetail;
  albumDetailLoading: boolean = false;
  albumDetailError: string = '';

  private readonly repository: MusicRepository;
  private importer?: MediaImporter;
  private artworkCache?: ArtworkCache;
  private settings?: SettingsRepository;
  private initializePromise?: Promise<void>;
  private refreshGeneration: number = 0;
  private trackSortGeneration: number = 0;
  private albumSortGeneration: number = 0;
  private albumDetailGeneration: number = 0;

  async loadAlbumDetail(albumId: number): Promise<void> {
    const generation = ++this.albumDetailGeneration;
    this.albumDetailLoading = true;
    this.albumDetailError = '';
    this.albumDetail = undefined;
    try {
      const detail = await this.repository.getAlbumDetail(albumId);
      if (generation !== this.albumDetailGeneration) {
        return;
      }
      this.albumDetail = detail;
      if (detail === undefined) {
        this.albumDetailError = '专辑不存在或已从音乐库移除';
      }
    } catch (error) {
      if (generation === this.albumDetailGeneration) {
        this.albumDetailError = LibraryStore.errorMessageOf(error);
      }
    } finally {
      if (generation === this.albumDetailGeneration) {
        this.albumDetailLoading = false;
      }
    }
  }

  constructor(repository?: MusicRepository) {
    this.repository = repository === undefined ? new MusicRepository() : repository;
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
    this.settings?.setSongSort(field, direction === SortDirection.DESCENDING);
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
    this.settings?.setAlbumSort(field, direction === SortDirection.DESCENDING);
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
    if (this.importer === undefined || this.importing) {
      return;
    }
    this.importing = true;
    this.errorMessage = '';
    this.lastMessage = '';
    this.lastImportResult = undefined;
    this.importDetailItems = [];
    try {
      const result = await this.importer.selectAndImport((progress: ImportProgress) => {
        this.importProgress = progress;
      }, onStarted, (item: ImportItemResult) => {
        if (item.outcome !== ImportItemOutcome.IMPORTED) {
          this.importDetailItems = this.importDetailItems.concat([item]);
        }
      });
      this.lastImportResult = result;
      this.importDetailItems = result.items.filter((item: ImportItemResult) =>
        item.outcome !== ImportItemOutcome.IMPORTED);
      this.lastMessage = LibraryStore.importSummary(result);
      const refreshStartedAt = Date.now();
      await this.refresh();
      ImportPerformanceTrace.mark('post_import_refresh', refreshStartedAt);
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.importing = false;
    }
  }

  cancelImport(): void {
    this.importer?.cancel();
  }

  async clearLibrary(): Promise<void> {
    if (this.importer === undefined || this.importing) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    try {
      await playbackRuntime.prepareForLibraryClear();
      await this.importer.clearLibrary();
      this.lastMessage = '音乐库已清空，原始音乐文件没有被删除';
      await this.refresh();
    } catch (error) {
      this.errorMessage = LibraryStore.errorMessageOf(error);
    } finally {
      this.loading = false;
    }
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

  resolveArtworkPath(relativePath: string): string {
    if (relativePath.length === 0 || this.artworkCache === undefined) {
      return '';
    }
    return `file://${this.artworkCache.resolvePath(relativePath)}`;
  }

  trackSnapshot(): Array<TrackListItem> {
    return this.trackDataSource.snapshot();
  }

  private restoreSortSettings(): void {
    if (this.settings === undefined) {
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
    return `已导入 ${result.imported} 首，重复 ${result.duplicates} 首，失败 ${result.failed} 首`;
  }

  private static errorMessageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
