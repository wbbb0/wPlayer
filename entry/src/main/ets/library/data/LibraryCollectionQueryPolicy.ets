/** Bounded overview sizes keep detail queries independent from complete collection cardinality. */
export class LibraryCollectionQueryPolicy {
  static readonly ARTIST_ALBUM_PREVIEW_LIMIT: number = 12;
  static readonly ARTIST_TRACK_PREVIEW_LIMIT: number = 10;
  static readonly RELATED_ALBUM_PREVIEW_LIMIT: number = 12;
}
