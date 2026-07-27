import {
  AlbumDetail,
  AlbumListItem,
  AlbumSortField,
  ArtistDetail,
  ArtistReference,
  AvailabilityState,
  LibraryCatalog,
  LibraryPage,
  LibraryStatistics,
  MediaFileCheckCandidate,
  SortDirection,
  TrackAvailabilityUpdate,
  TrackDetail,
  TrackListItem,
  TrackNavigationTargets,
  TrackSortField,
  UnavailableTrackItem
} from '../model/LibraryModels';
import { PlaybackTrack, QueueTrack, ResumeState } from '../../playback/model/PlaybackModels';
import { LibraryDatabase } from './LibraryDatabase';
import { MusicLibraryAlbumQueries } from './MusicLibraryAlbumQueries';
import { MusicLibraryDetailQueries } from './MusicLibraryDetailQueries';
import { MusicLibraryMaintenanceQueries } from './MusicLibraryMaintenanceQueries';
import { MusicLibraryTrackQueries } from './MusicLibraryTrackQueries';
import {
  ArtworkAssetLookup,
  ArtworkCleanupCandidate,
  DuplicateCandidate,
  LibraryMaintenanceStatus,
  PaletteRefreshAsset
} from './MusicRepositoryTypes';

/**
 * Stable query facade for MusicRepository.
 * Domain reads and writes are delegated without changing repository invalidation.
 */
export class MusicLibraryQueries {
  private readonly track: MusicLibraryTrackQueries;
  private readonly album: MusicLibraryAlbumQueries;
  private readonly detail: MusicLibraryDetailQueries;
  private readonly maintenance: MusicLibraryMaintenanceQueries;

  constructor(database: LibraryDatabase) {
    this.track = new MusicLibraryTrackQueries(database);
    this.album = new MusicLibraryAlbumQueries(database);
    this.detail = new MusicLibraryDetailQueries(database);
    this.maintenance = new MusicLibraryMaintenanceQueries(database);
  }

  getStatistics(): Promise<LibraryStatistics> {
    return this.maintenance.getStatistics();
  }

  getTrackCatalog(field: TrackSortField, direction: SortDirection): Promise<LibraryCatalog> {
    return this.track.getTrackCatalog(field, direction);
  }

  getTrackPage(field: TrackSortField, direction: SortDirection,
    catalog: LibraryCatalog, offset: number, limit: number): Promise<LibraryPage<TrackListItem>> {
    return this.track.getTrackPage(field, direction, catalog, offset, limit);
  }

  getTrackPlaybackOrder(field: TrackSortField, direction: SortDirection): Promise<Array<TrackListItem>> {
    return this.track.getTrackPlaybackOrder(field, direction);
  }

  getPlaybackTrack(trackId: number): Promise<PlaybackTrack | undefined> {
    return this.track.getPlaybackTrack(trackId);
  }

  getPlaybackQueueTracks(trackIds: Array<number>): Promise<Array<QueueTrack>> {
    return this.track.getPlaybackQueueTracks(trackIds);
  }

  getResumeState(trackId: number): Promise<ResumeState> {
    return this.track.getResumeState(trackId);
  }

  savePlaybackState(trackId: number, positionMs: number, durationMs: number,
    completed: boolean): Promise<void> {
    return this.track.savePlaybackState(trackId, positionMs, durationMs, completed);
  }

  setTrackAvailability(trackId: number, state: AvailabilityState): Promise<void> {
    return this.track.setTrackAvailability(trackId, state);
  }

  setTrackAvailabilities(updates: Array<TrackAvailabilityUpdate>): Promise<void> {
    return this.track.setTrackAvailabilities(updates);
  }

  getMediaFileCheckCandidates(): Promise<Array<MediaFileCheckCandidate>> {
    return this.track.getMediaFileCheckCandidates();
  }

  getUnavailableTracks(): Promise<Array<UnavailableTrackItem>> {
    return this.track.getUnavailableTracks();
  }

  getAlbumCatalog(field: AlbumSortField, direction: SortDirection): Promise<LibraryCatalog> {
    return this.album.getAlbumCatalog(field, direction);
  }

  getAlbumPage(field: AlbumSortField, direction: SortDirection,
    catalog: LibraryCatalog, offset: number, limit: number): Promise<LibraryPage<AlbumListItem>> {
    return this.album.getAlbumPage(field, direction, catalog, offset, limit);
  }

  getAlbumDetail(albumId: number): Promise<AlbumDetail | undefined> {
    return this.detail.getAlbumDetail(albumId);
  }

  getAlbumArtists(albumId: number): Promise<Array<ArtistReference>> {
    return this.detail.getAlbumArtists(albumId);
  }

  getArtistDetail(artistId: number): Promise<ArtistDetail | undefined> {
    return this.detail.getArtistDetail(artistId);
  }

  getTrackNavigationTargets(trackId: number): Promise<TrackNavigationTargets | undefined> {
    return this.detail.getTrackNavigationTargets(trackId);
  }

  getTrackDetail(trackId: number): Promise<TrackDetail | undefined> {
    return this.detail.getTrackDetail(trackId);
  }

  hasUri(uri: string): Promise<boolean> {
    return this.maintenance.hasUri(uri);
  }

  hasUris(uris: Array<string>): Promise<Array<string>> {
    return this.maintenance.hasUris(uris);
  }

  findDuplicateCandidates(fileSize: number, quickFingerprint: string): Promise<Array<DuplicateCandidate>> {
    return this.maintenance.findDuplicateCandidates(fileSize, quickFingerprint);
  }

  updateFullFingerprint(trackId: number, fullFingerprint: string): Promise<void> {
    return this.maintenance.updateFullFingerprint(trackId, fullFingerprint);
  }

  findArtworkBySourceHash(sourceHash: string): Promise<ArtworkAssetLookup | undefined> {
    return this.maintenance.findArtworkBySourceHash(sourceHash);
  }

  getUnreferencedArtworkAssets(): Promise<Array<ArtworkCleanupCandidate>> {
    return this.maintenance.getUnreferencedArtworkAssets();
  }

  getReferencedArtworkPaths(): Promise<Array<string>> {
    return this.maintenance.getReferencedArtworkPaths();
  }

  getPaletteRefreshAssets(): Promise<Array<PaletteRefreshAsset>> {
    return this.maintenance.getPaletteRefreshAssets();
  }

  getOutdatedPaletteAssets(): Promise<Array<PaletteRefreshAsset>> {
    return this.maintenance.getOutdatedPaletteAssets();
  }

  getTrackPaletteAsset(trackId: number): Promise<PaletteRefreshAsset | undefined> {
    return this.maintenance.getTrackPaletteAsset(trackId);
  }

  getLibraryMaintenanceStatus(): Promise<LibraryMaintenanceStatus> {
    return this.maintenance.getLibraryMaintenanceStatus();
  }

  removeUnreferencedArtwork(assetId: number): Promise<void> {
    return this.maintenance.removeUnreferencedArtwork(assetId);
  }
}
