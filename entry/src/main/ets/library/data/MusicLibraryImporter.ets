import { relationalStore } from '@kit.ArkData';
import {
  ArtworkPictureType,
  AvailabilityState,
  CreditRole,
  ImportState,
  ParsedMetadata
} from '../model/LibraryModels';
import { MetadataNormalizer } from '../metadata/MetadataNormalizer';
import { SortKeyNormalizer } from '../metadata/SortKeyNormalizer';
import { DuplicatePolicy } from '../importer/DuplicatePolicy';
import { LibraryDatabase } from './LibraryDatabase';
import {
  ArtworkImportInput,
  ImportTrackResult,
  TrackImportInput
} from './MusicRepositoryTypes';

interface CreditGroup {
  role: CreditRole;
  names: Array<string>;
}

interface ArtworkReference {
  assetId?: number;
  sourceId?: number;
}

/**
 * Performs all writes required for one or more imported tracks in one database transaction.
 */
export class MusicLibraryImporter {
  private readonly database: LibraryDatabase;

  constructor(database: LibraryDatabase) {
    this.database = database;
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
        const duplicateResult: ImportTrackResult = {
          imported: false,
          trackId: existingTrackId,
          duplicateSource: 'uri'
        };
        return duplicateResult;
      }
      const duplicateTrackId = await this.findTrackIdByFingerprint(
        transaction, input.fileSize, input.quickFingerprint, input.fullFingerprint
      );
      if (duplicateTrackId !== undefined) {
        return { imported: false, trackId: duplicateTrackId, duplicateSource: 'content' };
      }
      const now = Date.now();
      const metadata = input.metadata;
      const mediaFileId = await transaction.insert('media_file', {
        uri: input.uri,
        display_name: input.displayName,
        file_size: input.fileSize,
        modified_at: input.modifiedAt,
        quick_fingerprint: input.quickFingerprint,
        content_fingerprint: input.fullFingerprint,
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
    if (artwork.smallHash === undefined || artwork.smallHash.length === 0 ||
      artwork.smallPath === undefined || artwork.smallPath.length === 0 ||
      artwork.smallFormat === undefined || artwork.smallFormat.length === 0 ||
      artwork.largeHash === undefined || artwork.largeHash.length === 0 ||
      artwork.largePath === undefined || artwork.largePath.length === 0 ||
      artwork.largeFormat === undefined || artwork.largeFormat.length === 0) {
      return {};
    }
    let assetId = await this.findArtworkAssetId(transaction, artwork.smallHash, artwork.largeHash);
    if (assetId === undefined) {
      assetId = await transaction.insert('artwork_asset', {
        small_hash: artwork.smallHash,
        small_path: artwork.smallPath,
        small_format: artwork.smallFormat,
        small_width: artwork.smallWidth === undefined ? 0 : artwork.smallWidth,
        small_height: artwork.smallHeight === undefined ? 0 : artwork.smallHeight,
        small_byte_size: artwork.smallByteSize === undefined ? 0 : artwork.smallByteSize,
        large_hash: artwork.largeHash,
        large_path: artwork.largePath,
        large_format: artwork.largeFormat,
        large_width: artwork.largeWidth === undefined ? 0 : artwork.largeWidth,
        large_height: artwork.largeHeight === undefined ? 0 : artwork.largeHeight,
        large_byte_size: artwork.largeByteSize === undefined ? 0 : artwork.largeByteSize,
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

  private async findArtworkAssetId(
    transaction: relationalStore.Transaction,
    smallHash: string,
    largeHash: string
  ): Promise<number | undefined> {
    const resultSet = await transaction.querySql(
      'SELECT id FROM artwork_asset WHERE small_hash = ? AND large_hash = ? LIMIT 1',
      [smallHash, largeHash]
    );
    try {
      return resultSet.goToNextRow() ? resultSet.getLong(0) : undefined;
    } finally {
      resultSet.close();
    }
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

  private async findTrackIdByFingerprint(
    transaction: relationalStore.Transaction,
    fileSize: number,
    quickFingerprint: string,
    fullFingerprint: string
  ): Promise<number | undefined> {
    if (fileSize <= 0 || quickFingerprint.length === 0 || fullFingerprint.length === 0) {
      return undefined;
    }
    const resultSet = await transaction.querySql(
      `SELECT t.id, f.quick_fingerprint, f.content_fingerprint FROM track t
       INNER JOIN media_file f ON f.id = t.media_file_id
       WHERE f.file_size = ? AND f.content_fingerprint = ? LIMIT 1`,
      [fileSize, fullFingerprint]
    );
    try {
      if (!resultSet.goToNextRow()) {
        return undefined;
      }
      return DuplicatePolicy.isConfirmedDuplicate(
        resultSet.getString(1), quickFingerprint, resultSet.getString(2), fullFingerprint
      ) ? resultSet.getLong(0) : undefined;
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
