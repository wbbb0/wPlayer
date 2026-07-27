import { relationalStore } from '@kit.ArkData';
import {
  AlbumListItem,
  ArtistReference,
  AvailabilityState,
  TrackListItem
} from '../model/LibraryModels';
import { RelationalStoreSafety } from './RelationalStoreSafety';

/**
 * Pure current-row mappings shared by library query domains.
 * Callers own ResultSet iteration and closure.
 */
export function trackListItemFromCurrentRow(resultSet: relationalStore.ResultSet): TrackListItem {
  try {
    return {
      id: resultSet.getLong(0),
      title: resultSet.getString(1),
      artistDisplay: resultSet.getString(2),
      albumDisplay: resultSet.getString(3),
      durationMs: resultSet.getLong(4),
      trackNumber: resultSet.getLong(5),
      discNumber: resultSet.getLong(6),
      smallArtworkHash: resultSet.getString(7),
      smallArtworkPath: resultSet.getString(8),
      artworkHash: resultSet.getString(9),
      artworkPath: resultSet.getString(10),
      artworkWidth: resultSet.getLong(11),
      artworkHeight: resultSet.getLong(12),
      palettePrimary: resultSet.getString(13),
      paletteSecondary: resultSet.getString(14),
      paletteAccent: resultSet.getString(15),
      sectionKey: resultSet.getString(16),
      availability: resultSet.getLong(17) as AvailabilityState
    };
  } catch (error) {
    throw RelationalStoreSafety.operationError('Unable to decode track list row', error);
  }
}

export function albumListItemFromCurrentRow(resultSet: relationalStore.ResultSet): AlbumListItem {
  try {
    return {
      id: resultSet.getLong(0),
      title: resultSet.getString(1),
      albumArtistDisplay: resultSet.getString(2),
      trackCount: resultSet.getLong(3),
      totalDurationMs: resultSet.getLong(4),
      artworkPath: resultSet.getString(5),
      artworkWidth: resultSet.getLong(6),
      artworkHeight: resultSet.getLong(7),
      palettePrimary: resultSet.getString(8),
      paletteSecondary: resultSet.getString(9),
      paletteAccent: resultSet.getString(10),
      sectionKey: resultSet.getString(11),
      unavailableTrackCount: resultSet.getLong(12)
    };
  } catch (error) {
    throw RelationalStoreSafety.operationError('Unable to decode album list row', error);
  }
}

export function artistReferenceFromCurrentRow(resultSet: relationalStore.ResultSet): ArtistReference {
  try {
    return {
      id: resultSet.getLong(0),
      name: resultSet.getString(1)
    };
  } catch (error) {
    throw RelationalStoreSafety.operationError('Unable to decode artist reference row', error);
  }
}
