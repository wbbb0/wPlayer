import { common } from '@kit.AbilityKit';
import { ArtworkCache } from '../artwork/ArtworkCache';
import { MusicRepository } from '../data/MusicRepository';
import { LibraryRemovalService } from '../maintenance/LibraryRemovalService';
import { FileCheckResult, ImportResult } from '../model/LibraryModels';
import { MediaImportSession } from './MediaImportSession';
import {
  FileCheckProgressCallback,
  ImportItemCallback,
  ImportLibraryChangedCallback,
  ImportProgressCallback,
  ImportStartedCallback
} from './MediaImportCallbacks';
import { MediaImportOperation } from './MediaImportOperation';
import { MediaArtworkPipeline } from './MediaArtworkPipeline';

export {
  ImportRefreshPhase
} from './MediaImportCallbacks';
export type {
  FileCheckProgressCallback,
  ImportItemCallback,
  ImportLibraryChangedCallback,
  ImportProgressCallback,
  ImportStartedCallback
} from './MediaImportCallbacks';

export class MediaImporter {
  private readonly context: common.UIAbilityContext;
  private readonly repository: MusicRepository;
  private readonly artworkCache: ArtworkCache;
  private readonly removalService: LibraryRemovalService;
  private readonly artworkPipeline: MediaArtworkPipeline;
  private activeOperation?: MediaImportOperation;

  constructor(context: common.UIAbilityContext, repository: MusicRepository, artworkCache: ArtworkCache,
    removalService?: LibraryRemovalService) {
    this.context = context;
    this.repository = repository;
    this.artworkCache = artworkCache;
    this.artworkPipeline = new MediaArtworkPipeline(repository, artworkCache);
    this.removalService = removalService === undefined ?
      new LibraryRemovalService(repository) : removalService;
  }

  isImporting(): boolean {
    return this.activeOperation !== undefined;
  }

  cancel(): void {
    this.activeOperation?.cancel();
  }

  async selectAndImport(onProgress?: ImportProgressCallback,
    onStarted?: ImportStartedCallback, onItem?: ImportItemCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<ImportResult> {
    const operation = this.beginOperation('An import is already running');
    const session = this.createSession(operation);
    try {
      return await session.selectAndImport(onProgress, onStarted, onItem, onLibraryChanged);
    } finally {
      await operation.cancelAndWait();
      this.finishOperation(operation);
    }
  }

  async checkLibrary(onProgress?: FileCheckProgressCallback,
    onLibraryChanged?: ImportLibraryChangedCallback): Promise<FileCheckResult> {
    const operation = this.beginOperation('Cannot check music files during an import');
    const session = this.createSession(operation);
    try {
      return await session.checkLibrary(onProgress, onLibraryChanged);
    } finally {
      await operation.cancelAndWait();
      this.finishOperation(operation);
    }
  }

  async clearLibrary(): Promise<void> {
    if (this.activeOperation !== undefined) {
      throw new Error('Cannot clear the library during an import');
    }
    const operation = new MediaImportOperation();
    await this.createSession(operation).clearLibrary();
  }

  scheduleArtworkStorageCleanup(): void {
    this.artworkPipeline.scheduleCleanup(
      (): boolean => this.activeOperation === undefined
    );
  }

  private beginOperation(message: string): MediaImportOperation {
    if (this.activeOperation !== undefined) {
      throw new Error(message);
    }
    const operation = new MediaImportOperation();
    this.activeOperation = operation;
    return operation;
  }

  private finishOperation(operation: MediaImportOperation): void {
    if (this.activeOperation === operation) {
      this.activeOperation = undefined;
    }
  }

  private createSession(operation: MediaImportOperation): MediaImportSession {
    return new MediaImportSession(
      this.context, this.repository, this.artworkCache, operation,
      this.artworkPipeline, this.removalService
    );
  }
}
