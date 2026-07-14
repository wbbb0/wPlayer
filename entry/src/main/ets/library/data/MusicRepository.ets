import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import {
  AlbumListItem,
  AlbumSortField,
  ArtworkPictureType,
  AvailabilityState,
  CreditRole,
  ImportState,
  LibraryStatistics,
  LibraryIndexPresentation,
  LibrarySection,
  LibrarySnapshot,
  ParsedArtwork,
  ParsedMetadata,
  TrackListItem,
  TrackSortField,
  SortDirection
} from '../model/LibraryModels';
import { MetadataNormalizer } from '../metadata/MetadataNormalizer';
import { SortKeyNormalizer } from '../metadata/SortKeyNormalizer';
import { LibraryDatabase } from './LibraryDatabase';

export interface ArtworkImportInput {
  metadata: ParsedArtwork;
  sourceHash?: string;
  thumbnailHash?: string;
  thumbnailPath?: string;
  thumbnailWidth?: number;
  thumbnailHeight?: number;
  thumbnailByteSize?: number;
  primary?: boolean;
}

export interface TrackImportInput {
  uri: string;
  displayName: string;
  fileSize: number;
  modifiedAt: number;
  quickFingerprint: string;
  authorizationPersisted: boolean;
  metadata: ParsedMetadata;
  artworks?: Array<ArtworkImportInput>;
}

export interface ImportTrackResult {
  imported: boolean;
  trackId: number;
}

export interface ArtworkAssetLookup {
  thumbnailHash: string;
  thumbnailPath: string;
  width: number;
  height: number;
  byteSize: number;
}

interface CreditGroup {
  role: CreditRole;
  names: Array<string>;
}

interface ArtworkReference {
  assetId?: number;
  sourceId?: number;
}

const URI_QUERY_BATCH_SIZE = 128;

export class MusicRepository {
  private readonly database: LibraryDatabase = new LibraryDatabase();

  initialize(context: common.Context): Promise<void> {
    return this.database.initialize(context);
  }

  close(): Promise<void> {
    return this.database.close();
  }

  clearLibrary(): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      const now = Date.now();
      await transaction.execute('DELETE FROM import_error');
      await transaction.execute('DELETE FROM import_job');
      await transaction.execute('DELETE FROM track_artwork');
      await transaction.execute('DELETE FROM track_credit');
      await transaction.execute('DELETE FROM track_genre');
      await transaction.execute('DELETE FROM track_tag_extra');
      await transaction.execute('DELETE FROM album_credit');
      await transaction.execute('DELETE FROM track');
      await transaction.execute('DELETE FROM media_file');
      await transaction.execute('DELETE FROM album');
      await transaction.execute('DELETE FROM person');
      await transaction.execute('DELETE FROM genre');
      await transaction.execute('DELETE FROM artwork_source');
      await transaction.execute(
        'UPDATE artwork_asset SET ref_count = 0, unreferenced_at = ? WHERE ref_count <> 0 OR unreferenced_at IS NULL',
        [now]
      );
    });
  }

  rebuildSortIndexes(): Promise<void> {
    return this.database.rebuildSortIndexes();
  }

  async getStatistics(): Promise<LibraryStatistics> {
    const store = this.database.getStore();
    return {
      trackCount: await this.readCount(store, 'SELECT COUNT(*) FROM track'),
      albumCount: await this.readCount(store, 'SELECT COUNT(*) FROM album'),
      artworkCount: await this.readCount(store, 'SELECT COUNT(*) FROM artwork_asset WHERE ref_count > 0')
    };
  }

  async getTracks(field: TrackSortField, direction: SortDirection): Promise<LibrarySnapshot<TrackListItem>> {
    const alphabetic = field === TrackSortField.TITLE || field === TrackSortField.ALBUM ||
      field === TrackSortField.ARTIST;
    const order = direction === SortDirection.ASCENDING ? 'ASC' : 'DESC';
    let sectionColumn = "'#'";
    let orderClause = `t.created_at ${order}, t.id ${order}`;
    if (field === TrackSortField.TITLE) {
      sectionColumn = 't.title_section';
      orderClause = `t.title_section = '#' ASC, t.title_natural_key ${order}, t.id ${order}`;
    } else if (field === TrackSortField.ALBUM) {
      sectionColumn = 't.album_section';
      orderClause = `t.album_section = '#' ASC, t.album_natural_key ${order}, t.id ${order}`;
    } else if (field === TrackSortField.ARTIST) {
      sectionColumn = 't.artist_section';
      orderClause = `t.artist_section = '#' ASC, t.artist_natural_key ${order}, t.id ${order}`;
    } else if (field === TrackSortField.RELEASE_DATE) {
      orderClause = `t.release_date_sort = 0 ASC, t.release_date_sort ${order}, t.id ${order}`;
    }
    const resultSet = await this.database.getStore().querySql(
      `SELECT t.id, t.title, t.artist_display, t.album_display, t.duration_ms,
        COALESCE(t.track_number, 0), COALESCE(t.disc_number, 0),
        COALESCE(a.thumbnail_path, ''), ${sectionColumn}
       FROM track t LEFT JOIN artwork_asset a ON a.id = t.primary_artwork_id
       ORDER BY ${orderClause}`
    );
    const items: Array<TrackListItem> = [];
    try {
      while (resultSet.goToNextRow()) {
        items.push({
          id: resultSet.getLong(0),
          title: resultSet.getString(1),
          artistDisplay: resultSet.getString(2),
          albumDisplay: resultSet.getString(3),
          durationMs: resultSet.getLong(4),
          trackNumber: resultSet.getLong(5),
          discNumber: resultSet.getLong(6),
          artworkPath: resultSet.getString(7),
          sectionKey: resultSet.getString(8)
        });
      }
    } finally {
      resultSet.close();
    }
    return {
      items: items,
      sections: alphabetic ? this.buildSections(items) : [],
      indexPresentation: alphabetic ? LibraryIndexPresentation.ALPHABET : LibraryIndexPresentation.SCROLLBAR
    };
  }

  async getAlbums(field: AlbumSortField, direction: SortDirection): Promise<LibrarySnapshot<AlbumListItem>> {
    const alphabetic = field === AlbumSortField.TITLE || field === AlbumSortField.ALBUM_ARTIST;
    const order = direction === SortDirection.ASCENDING ? 'ASC' : 'DESC';
    let sectionColumn = "'#'";
    let orderClause = `al.created_at ${order}, al.id ${order}`;
    if (field === AlbumSortField.TITLE) {
      sectionColumn = 'al.title_section';
      orderClause = `al.title_section = '#' ASC, al.title_natural_key ${order}, al.id ${order}`;
    } else if (field === AlbumSortField.ALBUM_ARTIST) {
      sectionColumn = 'al.artist_section';
      orderClause = `al.artist_section = '#' ASC, al.artist_natural_key ${order}, al.id ${order}`;
    } else if (field === AlbumSortField.RELEASE_DATE) {
      orderClause = `al.release_date_sort = 0 ASC, al.release_date_sort ${order}, al.id ${order}`;
    }
    const resultSet = await this.database.getStore().querySql(
      `SELECT al.id, al.title, al.album_artist_display, al.track_count,
        al.total_duration_ms, COALESCE(a.thumbnail_path, ''), ${sectionColumn}
       FROM album al LEFT JOIN artwork_asset a ON a.id = al.primary_artwork_id
       ORDER BY ${orderClause}`
    );
    const items: Array<AlbumListItem> = [];
    try {
      while (resultSet.goToNextRow()) {
        items.push({
          id: resultSet.getLong(0),
          title: resultSet.getString(1),
          albumArtistDisplay: resultSet.getString(2),
          trackCount: resultSet.getLong(3),
          totalDurationMs: resultSet.getLong(4),
          artworkPath: resultSet.getString(5),
          sectionKey: resultSet.getString(6)
        });
      }
    } finally {
      resultSet.close();
    }
    return {
      items: items,
      sections: alphabetic ? this.buildSections(items) : [],
      indexPresentation: alphabetic ? LibraryIndexPresentation.ALPHABET : LibraryIndexPresentation.SCROLLBAR
    };
  }

  async hasUri(uri: string): Promise<boolean> {
    const resultSet = await this.database.getStore().querySql(
      'SELECT 1 FROM media_file WHERE uri = ? LIMIT 1',
      [uri]
    );
    try {
      return resultSet.goToNextRow();
    } finally {
      resultSet.close();
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
      const resultSet = await this.database.getStore().querySql(
        `SELECT uri FROM media_file WHERE uri IN (${placeholders})`, batch
      );
      try {
        while (resultSet.goToNextRow()) {
          existingUris.push(resultSet.getString(0));
        }
      } finally {
        resultSet.close();
      }
    }
    return existingUris;
  }

  async findArtworkBySourceHash(sourceHash: string): Promise<ArtworkAssetLookup | undefined> {
    const resultSet = await this.database.getStore().querySql(
      `SELECT a.thumbnail_hash, a.thumbnail_path, a.width, a.height, a.byte_size
       FROM artwork_source s JOIN artwork_asset a ON a.id = s.asset_id
       WHERE s.source_hash = ? LIMIT 1`,
      [sourceHash]
    );
    try {
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      return {
        thumbnailHash: resultSet.getString(0),
        thumbnailPath: resultSet.getString(1),
        width: resultSet.getLong(2),
        height: resultSet.getLong(3),
        byteSize: resultSet.getLong(4)
      };
    } finally {
      resultSet.close();
    }
  }

  async getUnreferencedArtworkPaths(): Promise<Array<string>> {
    const resultSet = await this.database.getStore().querySql(
      'SELECT thumbnail_path FROM artwork_asset WHERE ref_count = 0 ORDER BY id'
    );
    const paths: Array<string> = [];
    try {
      while (resultSet.goToNextRow()) {
        paths.push(resultSet.getString(0));
      }
    } finally {
      resultSet.close();
    }
    return paths;
  }

  removeUnreferencedArtwork(path: string): Promise<void> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      await transaction.execute(
        'DELETE FROM artwork_asset WHERE thumbnail_path = ? AND ref_count = 0',
        [path]
      );
    });
  }

  async importTrack(input: TrackImportInput): Promise<ImportTrackResult> {
    const results = await this.importTracks([input]);
    return results[0];
  }

  importTracks(inputs: Array<TrackImportInput>): Promise<Array<ImportTrackResult>> {
    return this.database.enqueueWrite(async (transaction: relationalStore.Transaction) => {
      const results: Array<ImportTrackResult> = [];
      for (let index = 0; index < inputs.length; index += 1) {
        results.push(await this.importTrackInTransaction(transaction, inputs[index]));
      }
      return results;
    });
  }

  private async importTrackInTransaction(transaction: relationalStore.Transaction,
    input: TrackImportInput): Promise<ImportTrackResult> {
      const existingTrackId = await this.findTrackIdByUri(transaction, input.uri);
      if (existingTrackId !== undefined) {
        const duplicateResult: ImportTrackResult = { imported: false, trackId: existingTrackId };
        return duplicateResult;
      }
      const now = Date.now();
      const metadata = input.metadata;
      const mediaFileId = await transaction.insert('media_file', {
        uri: input.uri,
        display_name: input.displayName,
        file_size: input.fileSize,
        modified_at: input.modifiedAt,
        quick_fingerprint: input.quickFingerprint,
        format: metadata.format,
        mime_type: metadata.mimeType,
        authorization_persisted: input.authorizationPersisted ? 1 : 0,
        availability_state: AvailabilityState.AVAILABLE,
        import_state: ImportState.IMPORTED,
        last_checked_at: now,
        created_at: now,
        updated_at: now
      });

      const albumId = await this.ensureAlbum(transaction, metadata, now);
      const title = metadata.title.length > 0 ? metadata.title : input.displayName;
      const sortTitle = metadata.sortTitle.length > 0 ? metadata.sortTitle : title;
      const artistDisplay = metadata.artists.join(', ');
      const titleSort = SortKeyNormalizer.natural(sortTitle);
      const albumSort = SortKeyNormalizer.natural(metadata.album);
      const artistSort = SortKeyNormalizer.natural(artistDisplay);
      const trackValues: relationalStore.ValuesBucket = {
        media_file_id: mediaFileId,
        album_id: albumId === undefined ? null : albumId,
        title: title,
        sort_title: sortTitle,
        sort_key: MetadataNormalizer.normalizeKey(sortTitle),
        title_natural_key: titleSort.key,
        title_section: titleSort.section,
        artist_display: artistDisplay,
        artist_natural_key: artistSort.key,
        artist_section: artistSort.section,
        album_display: metadata.album,
        album_natural_key: albumSort.key,
        album_section: albumSort.section,
        album_artist_display: metadata.albumArtists.join(', '),
        composer_display: metadata.composers.join(', '),
        track_number: this.numberOrNull(metadata.trackNumber.value),
        total_track_count: this.numberOrNull(metadata.trackNumber.total),
        track_number_raw: metadata.trackNumber.raw === undefined ? '' : metadata.trackNumber.raw,
        disc_number: this.numberOrNull(metadata.discNumber.value),
        total_disc_count: this.numberOrNull(metadata.discNumber.total),
        disc_number_raw: metadata.discNumber.raw === undefined ? '' : metadata.discNumber.raw,
        release_date_raw: metadata.releaseDate.raw === undefined ? '' : metadata.releaseDate.raw,
        release_year: this.numberOrNull(metadata.releaseDate.year),
        release_month: this.numberOrNull(metadata.releaseDate.month),
        release_day: this.numberOrNull(metadata.releaseDate.day),
        release_date_precision: metadata.releaseDate.precision,
        release_date_sort: SortKeyNormalizer.date(metadata.releaseDate),
        original_release_date_raw: metadata.originalReleaseDate.raw === undefined ? '' : metadata.originalReleaseDate.raw,
        original_release_year: this.numberOrNull(metadata.originalReleaseDate.year),
        original_release_month: this.numberOrNull(metadata.originalReleaseDate.month),
        original_release_day: this.numberOrNull(metadata.originalReleaseDate.day),
        original_release_date_precision: metadata.originalReleaseDate.precision,
        duration_ms: metadata.durationMs,
        sample_rate: metadata.sampleRate,
        channel_count: metadata.channelCount,
        bits_per_sample: metadata.bitsPerSample,
        bit_rate: metadata.bitRate,
        created_at: now,
        updated_at: now
      };
      const trackId = await transaction.insert('track', trackValues);

      await this.insertCredits(transaction, trackId, metadata);
      await this.insertGenres(transaction, trackId, metadata.genres);
      await this.insertRawTags(transaction, trackId, metadata.rawTags);
      const primaryArtworkId = await this.insertArtworks(
        transaction,
        trackId,
        input.artworks === undefined ? [] : input.artworks,
        now
      );
      if (primaryArtworkId !== undefined) {
        await transaction.execute('UPDATE track SET primary_artwork_id = ? WHERE id = ?', [primaryArtworkId, trackId]);
      }
      if (albumId !== undefined) {
        await transaction.execute(
          `UPDATE album SET track_count = track_count + 1,
            total_duration_ms = total_duration_ms + ?,
            primary_artwork_id = COALESCE(primary_artwork_id, ?), updated_at = ? WHERE id = ?`,
          [metadata.durationMs, primaryArtworkId === undefined ? null : primaryArtworkId, now, albumId]
        );
      }
      const importedResult: ImportTrackResult = { imported: true, trackId: trackId };
      return importedResult;
  }

  private async ensureAlbum(
    transaction: relationalStore.Transaction,
    metadata: ParsedMetadata,
    now: number
  ): Promise<number | undefined> {
    const identityKey = MetadataNormalizer.albumIdentity(metadata);
    if (identityKey.length === 0) {
      return undefined;
    }
    const existingId = await this.findId(transaction, 'album', 'identity_key', identityKey);
    if (existingId !== undefined) {
      return existingId;
    }
    const albumArtistKey = metadata.albumArtists
      .map((name: string) => MetadataNormalizer.normalizeKey(name))
      .join('\u001F');
    const albumArtistDisplay = metadata.albumArtists.join(', ');
    const titleSort = SortKeyNormalizer.natural(metadata.album);
    const artistSort = SortKeyNormalizer.natural(albumArtistDisplay);
    const albumId = await transaction.insert('album', {
      identity_key: identityKey,
      title: metadata.album,
      title_key: MetadataNormalizer.normalizeKey(metadata.album),
      sort_title_key: MetadataNormalizer.normalizeKey(metadata.album),
      title_natural_key: titleSort.key,
      title_section: titleSort.section,
      album_artist_display: albumArtistDisplay,
      album_artist_key: albumArtistKey,
      artist_natural_key: artistSort.key,
      artist_section: artistSort.section,
      release_date_raw: metadata.releaseDate.raw === undefined ? '' : metadata.releaseDate.raw,
      release_year: this.numberOrNull(metadata.releaseDate.year),
      release_month: this.numberOrNull(metadata.releaseDate.month),
      release_day: this.numberOrNull(metadata.releaseDate.day),
      release_date_precision: metadata.releaseDate.precision,
      release_date_sort: SortKeyNormalizer.date(metadata.releaseDate),
      track_count: 0,
      total_duration_ms: 0,
      created_at: now,
      updated_at: now
    });
    for (let index = 0; index < metadata.albumArtists.length; index += 1) {
      const personId = await this.ensurePerson(transaction, metadata.albumArtists[index]);
      await transaction.insert('album_credit', {
        album_id: albumId,
        person_id: personId,
        ordinal: index
      });
    }
    return albumId;
  }

  private async insertCredits(
    transaction: relationalStore.Transaction,
    trackId: number,
    metadata: ParsedMetadata
  ): Promise<void> {
    const groups: Array<CreditGroup> = [
      { role: CreditRole.TRACK_ARTIST, names: metadata.artists },
      { role: CreditRole.COMPOSER, names: metadata.composers },
      { role: CreditRole.LYRICIST, names: metadata.lyricists },
      { role: CreditRole.CONDUCTOR, names: metadata.conductors },
      { role: CreditRole.PERFORMER, names: metadata.performers }
    ];
    for (let groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
      const group = groups[groupIndex];
      for (let index = 0; index < group.names.length; index += 1) {
        const personId = await this.ensurePerson(transaction, group.names[index]);
        await transaction.insert('track_credit', {
          track_id: trackId,
          person_id: personId,
          role: group.role,
          ordinal: index
        });
      }
    }
  }

  private async insertGenres(
    transaction: relationalStore.Transaction,
    trackId: number,
    genres: Array<string>
  ): Promise<void> {
    for (let index = 0; index < genres.length; index += 1) {
      const name = genres[index];
      const key = MetadataNormalizer.normalizeKey(name);
      let genreId = await this.findId(transaction, 'genre', 'name_key', key);
      if (genreId === undefined) {
        genreId = await transaction.insert('genre', { name: name, name_key: key });
      }
      await transaction.insert('track_genre', {
        track_id: trackId,
        genre_id: genreId,
        ordinal: index
      });
    }
  }

  private async insertRawTags(
    transaction: relationalStore.Transaction,
    trackId: number,
    rawTags: Map<string, Array<string>>
  ): Promise<void> {
    const buckets: Array<relationalStore.ValuesBucket> = [];
    rawTags.forEach((values: Array<string>, key: string) => {
      for (let index = 0; index < values.length; index += 1) {
        buckets.push({
          track_id: trackId,
          tag_key: key,
          ordinal: index,
          raw_value: values[index]
        });
      }
    });
    if (buckets.length > 0) {
      await transaction.batchInsert('track_tag_extra', buckets);
    }
  }

  private async insertArtworks(
    transaction: relationalStore.Transaction,
    trackId: number,
    artworks: Array<ArtworkImportInput>,
    now: number
  ): Promise<number | undefined> {
    let primaryAssetId: number | undefined = undefined;
    let primaryScore = Number.MAX_SAFE_INTEGER;
    for (let index = 0; index < artworks.length; index += 1) {
      const artwork = artworks[index];
      const reference = await this.ensureArtworkReference(transaction, artwork, now);
      await transaction.insert('track_artwork', {
        track_id: trackId,
        source_id: reference.sourceId === undefined ? null : reference.sourceId,
        asset_id: reference.assetId === undefined ? null : reference.assetId,
        picture_type: artwork.metadata.pictureType,
        ordinal: artwork.metadata.ordinal,
        description: artwork.metadata.description,
        mime_type: artwork.metadata.mimeType,
        width: artwork.metadata.width,
        height: artwork.metadata.height,
        color_depth: artwork.metadata.colorDepth,
        byte_offset: artwork.metadata.byteOffset,
        byte_length: artwork.metadata.byteLength,
        payload_offset: artwork.metadata.payloadOffset,
        unsynchronized: artwork.metadata.unsynchronized ? 1 : 0
      });
      if (reference.assetId !== undefined) {
        await transaction.execute(
          'UPDATE artwork_asset SET ref_count = ref_count + 1, unreferenced_at = NULL WHERE id = ?',
          [reference.assetId]
        );
        const score = artwork.primary === true ? -1 : this.artworkFallbackScore(artwork.metadata.pictureType);
        if (score < primaryScore) {
          primaryScore = score;
          primaryAssetId = reference.assetId;
        }
      }
    }
    return primaryAssetId;
  }

  private async ensureArtworkReference(
    transaction: relationalStore.Transaction,
    artwork: ArtworkImportInput,
    now: number
  ): Promise<ArtworkReference> {
    if (artwork.sourceHash !== undefined && artwork.sourceHash.length > 0) {
      const existingSource = await this.findArtworkSource(transaction, artwork.sourceHash);
      if (existingSource !== undefined) {
        return existingSource;
      }
    }
    if (artwork.thumbnailHash === undefined || artwork.thumbnailHash.length === 0 ||
      artwork.thumbnailPath === undefined || artwork.thumbnailPath.length === 0) {
      return {};
    }
    let assetId = await this.findId(transaction, 'artwork_asset', 'thumbnail_hash', artwork.thumbnailHash);
    if (assetId === undefined) {
      assetId = await transaction.insert('artwork_asset', {
        thumbnail_hash: artwork.thumbnailHash,
        thumbnail_path: artwork.thumbnailPath,
        width: artwork.thumbnailWidth === undefined ? 0 : artwork.thumbnailWidth,
        height: artwork.thumbnailHeight === undefined ? 0 : artwork.thumbnailHeight,
        byte_size: artwork.thumbnailByteSize === undefined ? 0 : artwork.thumbnailByteSize,
        ref_count: 0,
        unreferenced_at: now,
        created_at: now
      });
    }
    if (artwork.sourceHash === undefined || artwork.sourceHash.length === 0) {
      return { assetId: assetId };
    }
    let sourceId = await this.findId(transaction, 'artwork_source', 'source_hash', artwork.sourceHash);
    if (sourceId === undefined) {
      sourceId = await transaction.insert('artwork_source', {
        source_hash: artwork.sourceHash,
        asset_id: assetId,
        mime_type: artwork.metadata.mimeType,
        width: artwork.metadata.width,
        height: artwork.metadata.height,
        byte_size: artwork.metadata.byteLength,
        created_at: now
      });
    }
    return { assetId: assetId, sourceId: sourceId };
  }

  private async findArtworkSource(
    transaction: relationalStore.Transaction,
    sourceHash: string
  ): Promise<ArtworkReference | undefined> {
    const resultSet = await transaction.querySql(
      'SELECT id, asset_id FROM artwork_source WHERE source_hash = ? LIMIT 1',
      [sourceHash]
    );
    try {
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      const reference: ArtworkReference = {
        sourceId: resultSet.getLong(0),
        assetId: resultSet.getLong(1)
      };
      return reference;
    } finally {
      resultSet.close();
    }
  }

  private async ensurePerson(transaction: relationalStore.Transaction, name: string): Promise<number> {
    const key = MetadataNormalizer.normalizeKey(name);
    const existingId = await this.findId(transaction, 'person', 'name_key', key);
    if (existingId !== undefined) {
      return existingId;
    }
    return transaction.insert('person', {
      name: name,
      name_key: key,
      sort_name_key: key
    });
  }

  private async findTrackIdByUri(
    transaction: relationalStore.Transaction,
    uri: string
  ): Promise<number | undefined> {
    const resultSet = await transaction.querySql(
      `SELECT t.id FROM track t
       INNER JOIN media_file f ON f.id = t.media_file_id
       WHERE f.uri = ? LIMIT 1`,
      [uri]
    );
    try {
      return resultSet.goToNextRow() ? resultSet.getLong(0) : undefined;
    } finally {
      resultSet.close();
    }
  }

  private async findId(
    transaction: relationalStore.Transaction,
    table: string,
    column: string,
    value: string
  ): Promise<number | undefined> {
    const resultSet = await transaction.querySql(
      `SELECT id FROM ${table} WHERE ${column} = ? LIMIT 1`,
      [value]
    );
    try {
      return resultSet.goToNextRow() ? resultSet.getLong(0) : undefined;
    } finally {
      resultSet.close();
    }
  }

  private async readCount(store: relationalStore.RdbStore, sql: string): Promise<number> {
    const resultSet = await store.querySql(sql);
    try {
      return resultSet.goToNextRow() ? resultSet.getLong(0) : 0;
    } finally {
      resultSet.close();
    }
  }

  private buildSections<T extends TrackListItem | AlbumListItem>(items: Array<T>): Array<LibrarySection> {
    const sections: Array<LibrarySection> = [];
    let previous = '';
    for (let index = 0; index < items.length; index += 1) {
      const section = items[index].sectionKey;
      if (section !== previous) {
        sections.push({ label: section, startIndex: index });
        previous = section;
      }
    }
    return sections;
  }

  private numberOrNull(value?: number): number | null {
    return value === undefined ? null : value;
  }

  private artworkFallbackScore(pictureType: ArtworkPictureType): number {
    switch (pictureType) {
      case ArtworkPictureType.FRONT_COVER:
        return 0;
      case ArtworkPictureType.OTHER:
        return 1;
      case ArtworkPictureType.MEDIA:
        return 2;
      case ArtworkPictureType.LEAFLET:
        return 3;
      case ArtworkPictureType.BACK_COVER:
        return 4;
      default:
        return 100;
    }
  }
}
