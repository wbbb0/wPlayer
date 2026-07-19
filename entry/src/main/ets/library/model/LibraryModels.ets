export enum MediaFormat {
  MP3 = 'mp3',
  FLAC = 'flac'
}

export enum AvailabilityState {
  AVAILABLE = 0,
  UNAVAILABLE = 1,
  AUTHORIZATION_REVOKED = 2,
  CORRUPTED = 3
}

export enum ImportState {
  PENDING = 0,
  IMPORTED = 1,
  FAILED = 2
}

export enum CreditRole {
  TRACK_ARTIST = 0,
  ALBUM_ARTIST = 1,
  COMPOSER = 2,
  LYRICIST = 3,
  CONDUCTOR = 4,
  PERFORMER = 5
}

export enum SortDirection {
  ASCENDING = 0,
  DESCENDING = 1
}

export enum TrackSortField {
  TITLE = 0,
  ALBUM = 1,
  ARTIST = 2,
  RELEASE_DATE = 3,
  ADDED_AT = 4
}

export enum AlbumSortField {
  TITLE = 0,
  ALBUM_ARTIST = 1,
  RELEASE_DATE = 2,
  ADDED_AT = 3
}

export enum PlaylistKind {
  USER = 0,
  COMPLETED_HISTORY = 1
}

export enum PlaylistItemSource {
  MANUAL = 0,
  IMPORT = 1,
  AUTO_COMPLETED = 2
}

export enum PlaylistSortField {
  NAME = 0,
  LAST_PLAYED = 1,
  UPDATED_AT = 2,
  CREATED_AT = 3,
  TRACK_COUNT = 4,
  TOTAL_DURATION = 5
}

export enum PlaylistTrackSortField {
  MANUAL = 0,
  ADDED_AT = 1,
  TITLE = 2,
  ARTIST = 3,
  ALBUM = 4,
  RELEASE_DATE = 5,
  DURATION = 6,
  LAST_PLAYED = 7,
  LAST_COMPLETED = 8
}

export enum LibraryIndexPresentation {
  ALPHABET = 0,
  SCROLLBAR = 1
}

export interface LibrarySection {
  label: string;
  startIndex: number;
}

export interface LibrarySnapshot<T> {
  items: Array<T>;
  sections: Array<LibrarySection>;
  indexPresentation: LibraryIndexPresentation;
}

/** Stable metadata for the complete logical result set behind a paged list. */
export interface LibraryCatalog {
  totalCount: number;
  sections: Array<LibrarySection>;
  indexPresentation: LibraryIndexPresentation;
}

/** A page whose offset is expressed in complete-result-set indexes. */
export interface LibraryPage<T> {
  offset: number;
  items: Array<T>;
}

export enum ArtworkPictureType {
  OTHER = 0,
  FILE_ICON = 1,
  OTHER_FILE_ICON = 2,
  FRONT_COVER = 3,
  BACK_COVER = 4,
  LEAFLET = 5,
  MEDIA = 6,
  LEAD_ARTIST = 7,
  ARTIST = 8,
  CONDUCTOR = 9,
  BAND = 10,
  COMPOSER = 11,
  LYRICIST = 12,
  RECORDING_LOCATION = 13,
  DURING_RECORDING = 14,
  DURING_PERFORMANCE = 15,
  VIDEO_CAPTURE = 16,
  BRIGHT_COLORED_FISH = 17,
  ILLUSTRATION = 18,
  BAND_LOGO = 19,
  PUBLISHER_LOGO = 20
}

export interface ParsedNumberPair {
  value?: number;
  total?: number;
  raw?: string;
}

export interface ParsedDate {
  raw?: string;
  year?: number;
  month?: number;
  day?: number;
  precision: number;
}

export interface ParsedArtwork {
  pictureType: ArtworkPictureType;
  mimeType: string;
  description: string;
  width: number;
  height: number;
  colorDepth: number;
  byteOffset: number;
  byteLength: number;
  payloadOffset: number;
  ordinal: number;
  unsynchronized: boolean;
}

export interface ParsedMetadata {
  format: MediaFormat;
  title: string;
  sortTitle: string;
  album: string;
  albumArtists: Array<string>;
  artists: Array<string>;
  composers: Array<string>;
  lyricists: Array<string>;
  lyrics: string;
  conductors: Array<string>;
  performers: Array<string>;
  genres: Array<string>;
  trackNumber: ParsedNumberPair;
  discNumber: ParsedNumberPair;
  releaseDate: ParsedDate;
  originalReleaseDate: ParsedDate;
  durationMs: number;
  sampleRate: number;
  channelCount: number;
  bitsPerSample: number;
  bitRate: number;
  mimeType: string;
  artworks: Array<ParsedArtwork>;
  rawTags: Map<string, Array<string>>;
}

export interface TrackListItem {
  id: number;
  title: string;
  artistDisplay: string;
  albumDisplay: string;
  durationMs: number;
  trackNumber: number;
  discNumber: number;
  smallArtworkHash: string;
  smallArtworkPath: string;
  artworkHash: string;
  artworkPath: string;
  artworkWidth: number;
  artworkHeight: number;
  palettePrimary: string;
  paletteSecondary: string;
  paletteAccent: string;
  sectionKey: string;
}

export interface ArtistReference {
  id: number;
  name: string;
}

export interface AlbumReference {
  id: number;
  title: string;
  palettePrimary: string;
}

export enum LibraryEntityKind {
  ARTIST = 0,
  ALBUM = 1
}

export interface LibraryEntityIdentity {
  kind: LibraryEntityKind;
  id: number;
}

export interface LibraryNavigationTarget {
  identity: LibraryEntityIdentity;
  title: string;
  palettePrimary: string;
}

export interface TrackNavigationTargets {
  trackId: number;
  trackArtists: Array<ArtistReference>;
  albumArtists: Array<ArtistReference>;
  album?: AlbumReference;
}

export interface AlbumListItem {
  id: number;
  title: string;
  albumArtistDisplay: string;
  trackCount: number;
  totalDurationMs: number;
  artworkPath: string;
  artworkWidth: number;
  artworkHeight: number;
  palettePrimary: string;
  paletteSecondary: string;
  paletteAccent: string;
  sectionKey: string;
}

export interface AlbumDetail {
  album: AlbumListItem;
  albumArtists: Array<ArtistReference>;
  relatedAlbums: Array<AlbumListItem>;
  releaseYear: number;
  genreDisplay: string;
  tracks: Array<TrackListItem>;
}

export interface ArtistDetail {
  artist: ArtistReference;
  albumCount: number;
  trackCount: number;
  totalDurationMs: number;
  albums: Array<AlbumListItem>;
  tracks: Array<TrackListItem>;
}

export interface PlaylistSummary {
  id: number;
  kind: PlaylistKind;
  name: string;
  itemSortField: PlaylistTrackSortField;
  itemSortDirection: SortDirection;
  trackCount: number;
  totalDurationMs: number;
  createdAt: number;
  updatedAt: number;
  lastPlayedAt: number;
}

export interface PlaylistTrackItem extends TrackListItem {
  position: number;
  addedAt: number;
  source: PlaylistItemSource;
  firstQualifiedAt: number;
  lastQualifiedAt: number;
  lastPlayedAt: number;
  lastCompletedAt: number;
}

export interface PlaylistDetail {
  playlist: PlaylistSummary;
  items: Array<PlaylistTrackItem>;
  offset: number;
  totalCount: number;
}

export interface PlaylistItemInput {
  trackId: number;
  source: PlaylistItemSource;
  qualifiedAt?: number;
}

export interface PlaylistMutationResult {
  requested: number;
  inserted: number;
  alreadyPresent: number;
  unavailable: number;
}

export interface PlaylistTransferTrack {
  trackId: number;
  uri: string;
  displayName: string;
  title: string;
  artistDisplay: string;
  durationMs: number;
  firstQualifiedAt: number;
  lastQualifiedAt: number;
}

export interface LibraryStatistics {
  trackCount: number;
  albumCount: number;
  artworkCount: number;
}

export interface ImportProgress {
  total: number;
  processed: number;
  imported: number;
  duplicates: number;
  failed: number;
  currentName: string;
}

export interface ImportResult {
  imported: number;
  duplicates: number;
  failed: number;
  items: Array<ImportItemResult>;
}

export enum ImportItemOutcome {
  IMPORTED = 'imported',
  DUPLICATE = 'duplicate',
  FAILED = 'failed'
}

export enum ImportItemDetailKind {
  URI_DUPLICATE = 'uri_duplicate',
  CONTENT_DUPLICATE = 'content_duplicate',
  BATCH_DUPLICATE = 'batch_duplicate',
  FAILED = 'failed'
}

export interface ImportItemResult {
  uri: string;
  displayName: string;
  outcome: ImportItemOutcome;
  reason: string;
  detailKind?: ImportItemDetailKind;
  duplicateTrackId?: number;
  duplicateSourceUri?: string;
}

export interface MetadataReadResult {
  metadata: ParsedMetadata;
  fileName: string;
  fileSize: number;
  modifiedAt: number;
  quickFingerprint: string;
  fullFingerprint: string;
}
