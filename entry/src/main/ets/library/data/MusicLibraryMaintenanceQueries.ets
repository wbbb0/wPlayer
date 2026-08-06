import { relationalStore } from '@kit.ArkData';
import {
  AvailabilityState,
  LibraryStatistics
} from '../model/LibraryModels';
import { ARTWORK_PALETTE_VERSION } from '../artwork/ArtworkPaletteExtractor';
import { ArtworkEncodingPolicy } from '../artwork/ArtworkEncodingPolicy';
import { LibraryDatabase } from './LibraryDatabase';
import {
  ArtworkAssetLookup,
  ArtworkCleanupCandidate,
  DuplicateCandidate,
  LibraryMaintenanceItem,
  LibraryMaintenanceKind,
  LibraryMaintenanceStatus,
  PaletteRefreshAsset
} from './MusicRepositoryTypes';
import { RelationalStoreSafety } from './RelationalStoreSafety';

const URI_QUERY_BATCH_SIZE = 128;

/**
 * Owns library-maintenance reads and writes. MusicRepository remains responsible for invalidating observable projections.
 */
export class MusicLibraryMaintenanceQueries {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
  }

  async getStatistics(): Promise<LibraryStatistics> {
    const store = this.database.getStore();
    return {
      trackCount: await this.readCount(store, 'SELECT COUNT(*) FROM track'),
      albumCount: await this.readCount(store, 'SELECT COUNT(*) FROM album'),
      artworkCount: await this.readCount(store, 'SELECT COUNT(*) FROM artwork_asset WHERE ref_count > 0'),
      unavailableTrackCount: await this.readCount(
        store,
        `SELECT COUNT(*) FROM media_file WHERE availability_state <> ${AvailabilityState.AVAILABLE}`
      )
    };
  }


  async hasUri(uri: string): Promise<boolean> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        'SELECT 1 FROM media_file WHERE uri = ? LIMIT 1',
        [uri]
      );
      return resultSet.goToNextRow();
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to check media URI ${uri}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'media URI lookup');
    }
  }

  async hasUris(uris: Array<string>): Promise<Array<string>> {
    const existingUris: Array<string> = [];
    for (let offset = 0; offset < uris.length; offset += URI_QUERY_BATCH_SIZE) {
      const batch = uris.slice(offset, Math.min(offset + URI_QUERY_BATCH_SIZE, uris.length));
      if (batch.length === 0) {
        continue;
      }
      const placeholders = batch.map(() => '?').join(', ');
      let resultSet: relationalStore.ResultSet | undefined;
      try {
        resultSet = await this.database.getStore().querySql(
          `SELECT uri FROM media_file WHERE uri IN (${placeholders})`, batch
        );
        while (resultSet.goToNextRow()) {
          existingUris.push(resultSet.getString(0));
        }
      } catch (error) {
        throw RelationalStoreSafety.operationError(
          `Unable to check media URI batch at offset ${offset}`, error
        );
      } finally {
        RelationalStoreSafety.closeResultSet(resultSet, 'media URI batch lookup');
      }
    }
    return existingUris;
  }

  async findDuplicateCandidates(fileSize: number, quickFingerprint: string): Promise<Array<DuplicateCandidate>> {
    if (fileSize <= 0 || quickFingerprint.length === 0) {
      return [];
    }
    let resultSet: relationalStore.ResultSet | undefined;
    const candidates: Array<DuplicateCandidate> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT t.id, f.uri, f.content_fingerprint FROM media_file f
         JOIN track t ON t.media_file_id = f.id
         WHERE f.file_size = ? AND f.quick_fingerprint = ?`,
        [fileSize, quickFingerprint]
      );
      while (resultSet.goToNextRow()) {
        candidates.push({
          trackId: resultSet.getLong(0),
          uri: resultSet.getString(1),
          fullFingerprint: resultSet.getString(2)
        });
      }
      return candidates;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to find duplicate media candidates', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'duplicate media lookup');
    }
  }

  updateFullFingerprint(trackId: number, fullFingerprint: string): Promise<void> {
    if (fullFingerprint.length === 0) {
      return Promise.resolve();
    }
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await transaction.execute(
        `UPDATE media_file SET content_fingerprint = ?, updated_at = ?
         WHERE id = (SELECT media_file_id FROM track WHERE id = ?) AND content_fingerprint = ''`,
        [fullFingerprint, Date.now(), trackId]
      );
    });
  }

  async findArtworkBySourceHash(sourceHash: string): Promise<ArtworkAssetLookup | undefined> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT a.small_hash, a.small_path, a.small_format, a.small_width, a.small_height, a.small_byte_size,
          a.large_hash, a.large_path, a.large_format, a.large_width, a.large_height, a.large_byte_size,
          a.palette_primary, a.palette_secondary, a.palette_accent, a.palette_version,
          s.width, s.height, a.id, a.encoding_version
         FROM artwork_source s JOIN artwork_asset a ON a.id = s.asset_id
         WHERE s.source_hash = ? LIMIT 1`,
        [sourceHash]
      );
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      return {
        assetId: resultSet.getLong(18),
        smallHash: resultSet.getString(0),
        smallPath: resultSet.getString(1),
        smallFormat: resultSet.getString(2),
        smallWidth: resultSet.getLong(3),
        smallHeight: resultSet.getLong(4),
        smallByteSize: resultSet.getLong(5),
        largeHash: resultSet.getString(6),
        largePath: resultSet.getString(7),
        largeFormat: resultSet.getString(8),
        largeWidth: resultSet.getLong(9),
        largeHeight: resultSet.getLong(10),
        largeByteSize: resultSet.getLong(11),
        palettePrimary: resultSet.getString(12),
        paletteSecondary: resultSet.getString(13),
        paletteAccent: resultSet.getString(14),
        paletteVersion: resultSet.getLong(15),
        sourceWidth: resultSet.getLong(16),
        sourceHeight: resultSet.getLong(17),
        encodingVersion: resultSet.getLong(19)
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to find artwork source ${sourceHash}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artwork source lookup');
    }
  }

  async getUnreferencedArtworkAssets(): Promise<Array<ArtworkCleanupCandidate>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const candidates: Array<ArtworkCleanupCandidate> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT candidate.id, candidate.small_path, candidate.large_path,
          NOT EXISTS (
            SELECT 1 FROM artwork_asset active
            WHERE active.id <> candidate.id AND active.ref_count > 0
              AND (active.small_path = candidate.small_path OR active.large_path = candidate.small_path)
          ),
          NOT EXISTS (
            SELECT 1 FROM artwork_asset active
            WHERE active.id <> candidate.id AND active.ref_count > 0
              AND (active.small_path = candidate.large_path OR active.large_path = candidate.large_path)
          )
         FROM artwork_asset candidate WHERE candidate.ref_count = 0 ORDER BY candidate.id`
      );
      while (resultSet.goToNextRow()) {
        candidates.push({
          assetId: resultSet.getLong(0),
          smallPath: resultSet.getString(1),
          largePath: resultSet.getString(2),
          deleteSmall: resultSet.getLong(3) !== 0,
          deleteLarge: resultSet.getLong(4) !== 0
        });
      }
      return candidates;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read unreferenced artwork assets', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'unreferenced artwork lookup');
    }
  }

  async getReferencedArtworkPaths(): Promise<Array<string>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const paths: Array<string> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        'SELECT small_path, large_path FROM artwork_asset WHERE ref_count > 0'
      );
      while (resultSet.goToNextRow()) {
        const smallPath = resultSet.getString(0);
        const largePath = resultSet.getString(1);
        if (smallPath.length > 0 && paths.indexOf(smallPath) < 0) {
          paths.push(smallPath);
        }
        if (largePath.length > 0 && paths.indexOf(largePath) < 0) {
          paths.push(largePath);
        }
      }
      return paths;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read referenced artwork paths', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'referenced artwork lookup');
    }
  }

  async getPaletteRefreshAssets(): Promise<Array<PaletteRefreshAsset>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const assets: Array<PaletteRefreshAsset> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        'SELECT id, small_path, palette_version FROM artwork_asset WHERE ref_count > 0 ORDER BY id'
      );
      while (resultSet.goToNextRow()) {
        const asset: PaletteRefreshAsset = {
          id: resultSet.getLong(0),
          artworkPath: resultSet.getString(1),
          paletteVersion: resultSet.getLong(2)
        };
        assets.push(asset);
      }
      return assets;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read artwork palette refresh assets', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'artwork palette refresh lookup');
    }
  }

  async getOutdatedPaletteAssets(): Promise<Array<PaletteRefreshAsset>> {
    let resultSet: relationalStore.ResultSet | undefined;
    const assets: Array<PaletteRefreshAsset> = [];
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT id, small_path, palette_version FROM artwork_asset
         WHERE ref_count > 0 AND palette_version < ? ORDER BY id`,
        [ARTWORK_PALETTE_VERSION]
      );
      while (resultSet.goToNextRow()) {
        assets.push({
          id: resultSet.getLong(0),
          artworkPath: resultSet.getString(1),
          paletteVersion: resultSet.getLong(2)
        });
      }
      return assets;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read outdated artwork colors', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'outdated artwork color lookup');
    }
  }

  async getTrackPaletteAsset(trackId: number): Promise<PaletteRefreshAsset | undefined> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT a.id, a.small_path, a.palette_version
         FROM track t JOIN artwork_asset a ON a.id = t.primary_artwork_id
         WHERE t.id = ? AND a.ref_count > 0 LIMIT 1`,
        [trackId]
      );
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      return {
        id: resultSet.getLong(0),
        artworkPath: resultSet.getString(1),
        paletteVersion: resultSet.getLong(2)
      };
    } catch (error) {
      throw RelationalStoreSafety.operationError(`Unable to read artwork color for track ${trackId}`, error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'track artwork color lookup');
    }
  }

  async getLibraryMaintenanceStatus(): Promise<LibraryMaintenanceStatus> {
    let resultSet: relationalStore.ResultSet | undefined;
    const items: Array<LibraryMaintenanceItem> = [];
    let total = 0;
    try {
      resultSet = await this.database.getStore().querySql(
        `SELECT COUNT(*) FROM artwork_asset
         WHERE ref_count > 0 AND palette_version < ?`,
        [ARTWORK_PALETTE_VERSION]
      );
      if (resultSet.goToNextRow()) {
        const count = resultSet.getLong(0);
        if (count > 0) {
          items.push({ kind: LibraryMaintenanceKind.ARTWORK_COLORS, count: count });
          total += count;
        }
      }
      RelationalStoreSafety.closeResultSet(resultSet, 'library artwork color maintenance status');
      resultSet = undefined;
      resultSet = await this.database.getStore().querySql(
        `SELECT COUNT(*) FROM artwork_asset
         WHERE ref_count > 0 AND (
           encoding_version != ? OR LOWER(small_format) != ? OR LOWER(large_format) != ?
         )`,
        [ArtworkEncodingPolicy.VERSION, ArtworkEncodingPolicy.MIME_TYPE,
          ArtworkEncodingPolicy.MIME_TYPE]
      );
      if (resultSet.goToNextRow()) {
        const count = resultSet.getLong(0);
        if (count > 0) {
          items.push({ kind: LibraryMaintenanceKind.ARTWORK_VARIANTS, count: count });
          total += count;
        }
      }
      return { items: items, total: total };
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to inspect library maintenance status', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'library maintenance status');
    }
  }

  removeUnreferencedArtwork(assetId: number): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await transaction.execute(
        'DELETE FROM artwork_asset WHERE id = ? AND ref_count = 0',
        [assetId]
      );
    });
  }


  private async readCount(store: relationalStore.RdbStore, sql: string): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await store.querySql(sql);
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } catch (error) {
      throw RelationalStoreSafety.operationError('Unable to read catalog count', error);
    } finally {
      RelationalStoreSafety.closeResultSet(resultSet, 'catalog count lookup');
    }
  }
}
