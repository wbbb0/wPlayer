import { common } from '@kit.AbilityKit';
import { ArtworkCache, ArtworkCacheResult } from '../artwork/ArtworkCache';
import {
  ArtworkImportInput,
  MusicRepository,
  TrackImportInput
} from '../data/MusicRepository';
import { MetadataReader } from '../metadata/MetadataReader';
import {
  ArtworkPictureType,
  ImportProgress,
  ImportResult,
  MetadataReadResult,
  ParsedArtwork
} from '../model/LibraryModels';
import {
  persistReadPermissions,
  selectAudioFiles
} from './MediaPickerService';

export type ImportProgressCallback = (progress: ImportProgress) => void;

interface PreparedImport {
  input?: TrackImportInput;
  failed: boolean;
}

interface CommitOutcome {
  imported: boolean;
  failed: boolean;
}

const IMPORT_BATCH_SIZE = 16;
const PREPARATION_PARALLELISM = 3;

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

  async selectAndImport(onProgress?: ImportProgressCallback): Promise<ImportResult> {
    if (this.importing) {
      throw new Error('An import is already running');
    }
    this.importing = true;
    this.cancelRequested = false;
    this.artworkPreparations.clear();
    try {
      const uris = await selectAudioFiles(this.context);
      if (uris.length === 0) {
        return { imported: 0, duplicates: 0, failed: 0 };
      }
      return await this.importUris(uris, onProgress);
    } finally {
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
  }

  private async importUris(uris: Array<string>, onProgress?: ImportProgressCallback): Promise<ImportResult> {
    const permissionResult = await persistReadPermissions(uris);
    const progress: ImportProgress = {
      total: uris.length,
      processed: permissionResult.failedUris.length,
      imported: 0,
      duplicates: 0,
      failed: permissionResult.failedUris.length,
      currentName: ''
    };
    this.notify(onProgress, progress);

    const successfulUris = permissionResult.successfulUris;
    for (let batchOffset = 0; batchOffset < successfulUris.length; batchOffset += IMPORT_BATCH_SIZE) {
      if (this.cancelRequested) {
        break;
      }
      const uriBatch = successfulUris.slice(
        batchOffset, Math.min(batchOffset + IMPORT_BATCH_SIZE, successfulUris.length)
      );
      progress.currentName = '正在检查重复文件';
      this.notify(onProgress, progress);

      const existingUris = await this.repository.hasUris(uriBatch);
      const pendingUris: Array<string> = [];
      for (let index = 0; index < uriBatch.length; index += 1) {
        const uri = uriBatch[index];
        if (existingUris.indexOf(uri) >= 0) {
          progress.duplicates += 1;
          progress.processed += 1;
        } else {
          pendingUris.push(uri);
        }
      }
      this.notify(onProgress, progress);

      const preparedInputs: Array<TrackImportInput> = [];
      for (let prepareOffset = 0; prepareOffset < pendingUris.length;
        prepareOffset += PREPARATION_PARALLELISM) {
        if (this.cancelRequested) {
          break;
        }
        const preparationWindow = pendingUris.slice(
          prepareOffset, Math.min(prepareOffset + PREPARATION_PARALLELISM, pendingUris.length)
        );
        progress.currentName = `正在并行读取 ${preparationWindow.length} 个音乐文件`;
        this.notify(onProgress, progress);
        const prepared = await Promise.all(preparationWindow.map((uri: string) => this.prepareImport(uri)));
        for (let index = 0; index < prepared.length; index += 1) {
          const item = prepared[index];
          if (item.failed || item.input === undefined) {
            progress.failed += 1;
            progress.processed += 1;
          } else {
            preparedInputs.push(item.input);
          }
        }
        this.notify(onProgress, progress);
      }

      if (this.cancelRequested) {
        break;
      }
      if (preparedInputs.length > 0) {
        progress.currentName = `正在写入 ${preparedInputs.length} 首音乐`;
        this.notify(onProgress, progress);
        const results = await this.commitPreparedInputs(preparedInputs);
        for (let index = 0; index < results.length; index += 1) {
          if (results[index].failed) {
            progress.failed += 1;
          } else if (results[index].imported) {
            progress.imported += 1;
          } else {
            progress.duplicates += 1;
          }
          progress.processed += 1;
        }
        this.notify(onProgress, progress);
      }
    }
    progress.currentName = '';
    this.notify(onProgress, progress);
    return {
      imported: progress.imported,
      duplicates: progress.duplicates,
      failed: progress.failed
    };
  }

  private async prepareImport(uri: string): Promise<PreparedImport> {
    try {
      const readResult = await MetadataReader.read(uri);
      let artworks: Array<ArtworkImportInput>;
      try {
        artworks = await this.prepareArtworks(uri, readResult);
      } catch (error) {
        console.warn(`Artwork preparation failed: ${MediaImporter.errorMessage(error)}`);
        artworks = MediaImporter.artworkMetadataOnly(readResult.metadata.artworks);
      }
      return {
        failed: false,
        input: {
          uri: uri,
          displayName: readResult.fileName,
          fileSize: readResult.fileSize,
          modifiedAt: readResult.modifiedAt,
          quickFingerprint: readResult.quickFingerprint,
          authorizationPersisted: true,
          metadata: readResult.metadata,
          artworks: artworks
        }
      };
    } catch (error) {
      console.warn(`Music import failed: ${MediaImporter.errorMessage(error)}`);
      return { failed: true };
    }
  }

  private async commitPreparedInputs(inputs: Array<TrackImportInput>): Promise<Array<CommitOutcome>> {
    try {
      const batchResults = await this.repository.importTracks(inputs);
      const outcomes: Array<CommitOutcome> = [];
      for (let index = 0; index < batchResults.length; index += 1) {
        outcomes.push({ imported: batchResults[index].imported, failed: false });
      }
      return outcomes;
    } catch (error) {
      console.warn(`Batch import failed, retrying individually: ${MediaImporter.errorMessage(error)}`);
      const results: Array<CommitOutcome> = [];
      for (let index = 0; index < inputs.length; index += 1) {
        try {
          const result = await this.repository.importTrack(inputs[index]);
          results.push({ imported: result.imported, failed: false });
        } catch (itemError) {
          console.warn(`Music database write failed: ${MediaImporter.errorMessage(itemError)}`);
          results.push({ imported: false, failed: true });
        }
      }
      return results;
    }
  }

  private async prepareArtworks(uri: string, readResult: MetadataReadResult): Promise<Array<ArtworkImportInput>> {
    const parsedArtworks = readResult.metadata.artworks;
    const inputs: Array<ArtworkImportInput> = parsedArtworks.map((metadata: ParsedArtwork) => {
      const input: ArtworkImportInput = { metadata: metadata };
      return input;
    });
    const primaryIndex = MediaImporter.selectPrimaryArtwork(parsedArtworks);
    if (primaryIndex < 0) {
      return inputs;
    }
    const sourceBytes = MetadataReader.readArtworkBytes(uri, readResult.metadata, primaryIndex);
    const sourceHash = await ArtworkCache.hashSource(sourceBytes);
    const cached = await this.loadOrCacheArtwork(sourceHash, sourceBytes);
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

  private async loadOrCacheArtwork(sourceHash: string, sourceBytes: Uint8Array): Promise<ArtworkCacheResult> {
    const activePreparation = this.artworkPreparations.get(sourceHash);
    if (activePreparation !== undefined) {
      return activePreparation;
    }
    const preparation = this.resolveArtwork(sourceHash, sourceBytes);
    this.artworkPreparations.set(sourceHash, preparation);
    return preparation;
  }

  private async resolveArtwork(sourceHash: string, sourceBytes: Uint8Array): Promise<ArtworkCacheResult> {
    const existing = await this.repository.findArtworkBySourceHash(sourceHash);
    if (existing !== undefined) {
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
    return this.artworkCache.cache(sourceBytes, sourceHash);
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

  private static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
