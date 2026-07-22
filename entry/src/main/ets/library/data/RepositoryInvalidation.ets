export enum RepositoryProjection {
  LIBRARY_SUMMARY = 'library_summary',
  LIBRARY_TRACKS = 'library_tracks',
  LIBRARY_ALBUMS = 'library_albums',
  UNAVAILABLE_TRACKS = 'unavailable_tracks',
  PLAYLIST_SUMMARIES = 'playlist_summaries',
  PLAYLIST_DETAILS = 'playlist_details',
  PLAYLIST_PLAYBACK_ORDER = 'playlist_playback_order'
}

export enum PlaylistDetailTarget {
  NONE = 'none',
  IDS = 'ids',
  ALL = 'all'
}

export enum RepositoryInvalidationReason {
  LIBRARY_METADATA_CHANGED = 'library_metadata_changed',
  LIBRARY_ARTWORK_CHANGED = 'library_artwork_changed',
  SORT_INDEXES_REBUILT = 'sort_indexes_rebuilt',
  TRACK_AVAILABILITY_CHANGED = 'track_availability_changed',
  TRACKS_REMOVED = 'tracks_removed',
  LIBRARY_CLEARED = 'library_cleared',
  PLAYLIST_CREATED = 'playlist_created',
  PLAYLIST_RENAMED = 'playlist_renamed',
  PLAYLIST_DELETED = 'playlist_deleted',
  PLAYLIST_ITEMS_CHANGED = 'playlist_items_changed',
  PLAYLIST_ORDER_CHANGED = 'playlist_order_changed',
  PLAYLIST_PLAYED = 'playlist_played',
  PLAYBACK_COMPLETED = 'playback_completed'
}

export enum RepositoryContentChangeKind {
  METADATA = 'metadata',
  ARTWORK = 'artwork'
}

export class RepositoryInvalidation {
  readonly revision: number;
  readonly projections: Array<RepositoryProjection>;
  readonly playlistDetailTarget: PlaylistDetailTarget;
  readonly playlistIds: Array<number>;
  readonly reason: RepositoryInvalidationReason;

  constructor(revision: number, projections: Array<RepositoryProjection>,
    playlistDetailTarget: PlaylistDetailTarget, playlistIds: Array<number>,
    reason: RepositoryInvalidationReason) {
    this.revision = revision;
    this.projections = RepositoryInvalidation.uniqueProjections(projections);
    this.playlistDetailTarget = playlistDetailTarget;
    this.playlistIds = RepositoryInvalidation.uniqueIds(playlistIds);
    this.reason = reason;
  }

  hasProjection(projection: RepositoryProjection): boolean {
    return this.projections.includes(projection);
  }

  affectsPlaylistDetail(playlistId: number): boolean {
    if (!this.hasProjection(RepositoryProjection.PLAYLIST_DETAILS)) {
      return false;
    }
    if (this.playlistDetailTarget === PlaylistDetailTarget.ALL) {
      return true;
    }
    return this.playlistDetailTarget === PlaylistDetailTarget.IDS && this.playlistIds.includes(playlistId);
  }

  private static uniqueProjections(projections: Array<RepositoryProjection>): Array<RepositoryProjection> {
    const unique: Array<RepositoryProjection> = [];
    projections.forEach((projection: RepositoryProjection): void => {
      if (!unique.includes(projection)) {
        unique.push(projection);
      }
    });
    return unique;
  }

  private static uniqueIds(ids: Array<number>): Array<number> {
    const unique: Array<number> = [];
    ids.forEach((id: number): void => {
      if (id >= 0 && !unique.includes(id)) {
        unique.push(id);
      }
    });
    return unique;
  }
}

export type RepositoryInvalidationListener = (invalidation: RepositoryInvalidation) => void;

export class RepositoryInvalidationHub {
  private revision: number = 0;
  private readonly listeners: Array<RepositoryInvalidationListener> = [];

  addListener(listener: RepositoryInvalidationListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  removeListener(listener: RepositoryInvalidationListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  publish(projections: Array<RepositoryProjection>, reason: RepositoryInvalidationReason,
    playlistDetailTarget: PlaylistDetailTarget = PlaylistDetailTarget.NONE,
    playlistIds: Array<number> = []): RepositoryInvalidation {
    const invalidation = new RepositoryInvalidation(
      ++this.revision,
      projections,
      playlistDetailTarget,
      playlistIds,
      reason
    );
    const listeners = this.listeners.slice();
    listeners.forEach((listener: RepositoryInvalidationListener): void => {
      try {
        listener(invalidation);
      } catch (error) {
        console.warn(`Repository invalidation listener failed: ${RepositoryInvalidationHub.messageOf(error)}`);
      }
    });
    return invalidation;
  }

  currentRevision(): number {
    return this.revision;
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
