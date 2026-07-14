import {
  MediaFormat,
  ParsedMetadata
} from '../model/LibraryModels';

export class MetadataFactory {
  static empty(format: MediaFormat): ParsedMetadata {
    return {
      format: format,
      title: '',
      sortTitle: '',
      album: '',
      albumArtists: [],
      artists: [],
      composers: [],
      lyricists: [],
      conductors: [],
      performers: [],
      genres: [],
      trackNumber: {},
      discNumber: {},
      releaseDate: { precision: 0 },
      originalReleaseDate: { precision: 0 },
      durationMs: 0,
      sampleRate: 0,
      channelCount: 0,
      bitsPerSample: 0,
      bitRate: 0,
      mimeType: format === MediaFormat.FLAC ? 'audio/flac' : 'audio/mpeg',
      artworks: [],
      rawTags: new Map<string, Array<string>>()
    };
  }
}
