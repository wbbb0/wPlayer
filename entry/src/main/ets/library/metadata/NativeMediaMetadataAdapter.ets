import {
  NativeMediaArtwork,
  NativeParsedMedia
} from 'libwplayermedia.so';
import {
  ArtworkPictureType,
  MediaFormat,
  ParsedArtwork,
  ParsedMetadata
} from '../model/LibraryModels';
import { MetadataFactory } from './MetadataFactory';
import { MetadataNormalizer } from './MetadataNormalizer';

export class NativeMediaMetadataAdapter {
  static fromNative(parsed: NativeParsedMedia): ParsedMetadata {
    const format = parsed.format === MediaFormat.FLAC ? MediaFormat.FLAC : MediaFormat.MP3;
    const metadata = MetadataFactory.empty(format);
    const id3v1Fallbacks: Map<string, Array<string>> = new Map<string, Array<string>>();
    parsed.tags.forEach((entry): void => {
      if (format === MediaFormat.MP3 && entry.key.startsWith('__ID3V1_')) {
        const fallbackKey = entry.key.substring('__ID3V1_'.length);
        const fallbackValue = entry.value.trim();
        if (fallbackValue.length > 0) {
          id3v1Fallbacks.set(fallbackKey, [fallbackValue]);
        }
        return;
      }
      const key = format === MediaFormat.FLAC ?
        entry.key.trim().toUpperCase() : entry.key;
      if (key.length === 0) {
        return;
      }
      const values = NativeMediaMetadataAdapter.tagValues(format, key, entry.value);
      if (values.length === 0) {
        return;
      }
      const existing = metadata.rawTags.get(key) ?? [];
      existing.push(...values);
      metadata.rawTags.set(key, existing);
    });
    id3v1Fallbacks.forEach((values: Array<string>, key: string): void => {
      if (!metadata.rawTags.has(key)) {
        metadata.rawTags.set(key, values);
      }
    });
    parsed.artworks.forEach((artwork: NativeMediaArtwork): void => {
      metadata.artworks.push(NativeMediaMetadataAdapter.artwork(artwork));
    });
    metadata.durationMs = parsed.durationMs;
    metadata.sampleRate = parsed.sampleRate;
    metadata.channelCount = parsed.channelCount;
    metadata.bitsPerSample = parsed.bitsPerSample;
    NativeMediaMetadataAdapter.applyTags(metadata);
    return metadata;
  }

  private static tagValues(format: MediaFormat, key: string, rawValue: string): Array<string> {
    if (format === MediaFormat.FLAC || key === 'USLT') {
      const value = rawValue.replace(/\u0000+$/g, '').trim();
      return value.length > 0 ? [value] : [];
    }
    return rawValue.replace(/\u0000+$/g, '')
      .split('\u0000')
      .map((value: string): string => value.trim())
      .filter((value: string): boolean => value.length > 0);
  }

  private static artwork(nativeArtwork: NativeMediaArtwork): ParsedArtwork {
    const pictureType = nativeArtwork.pictureType >= ArtworkPictureType.OTHER &&
      nativeArtwork.pictureType <= ArtworkPictureType.PUBLISHER_LOGO ?
      nativeArtwork.pictureType as ArtworkPictureType : ArtworkPictureType.OTHER;
    return {
      pictureType: pictureType,
      mimeType: nativeArtwork.mimeType,
      description: nativeArtwork.description,
      width: nativeArtwork.width,
      height: nativeArtwork.height,
      colorDepth: nativeArtwork.colorDepth,
      byteOffset: nativeArtwork.byteOffset,
      byteLength: nativeArtwork.byteLength,
      payloadOffset: nativeArtwork.payloadOffset,
      ordinal: nativeArtwork.ordinal,
      unsynchronized: nativeArtwork.unsynchronized
    };
  }

  private static applyTags(metadata: ParsedMetadata): void {
    const tags = metadata.rawTags;
    if (metadata.format === MediaFormat.FLAC) {
      NativeMediaMetadataAdapter.applyFlacTags(metadata, tags);
    } else {
      NativeMediaMetadataAdapter.applyId3Tags(metadata, tags);
    }
  }

  private static applyId3Tags(metadata: ParsedMetadata,
    tags: Map<string, Array<string>>): void {
    metadata.title = MetadataNormalizer.first(tags, ['TIT2']);
    metadata.sortTitle = MetadataNormalizer.first(tags, ['TSOT']);
    metadata.album = MetadataNormalizer.first(tags, ['TALB']);
    metadata.albumArtists = MetadataNormalizer.values(tags, ['TPE2']);
    metadata.artists = MetadataNormalizer.values(tags, ['TPE1']);
    metadata.composers = MetadataNormalizer.values(tags, ['TCOM']);
    metadata.lyricists = MetadataNormalizer.values(tags, ['TEXT']);
    metadata.lyrics = MetadataNormalizer.first(tags, ['USLT']);
    metadata.conductors = MetadataNormalizer.values(tags, ['TPE3']);
    metadata.performers = MetadataNormalizer.values(tags, ['TPE4']);
    metadata.genres = MetadataNormalizer.values(tags, ['TCON']);
    metadata.trackNumber =
      MetadataNormalizer.parseNumberPair(MetadataNormalizer.first(tags, ['TRCK']));
    metadata.discNumber =
      MetadataNormalizer.parseNumberPair(MetadataNormalizer.first(tags, ['TPOS']));
    metadata.releaseDate =
      MetadataNormalizer.parseDate(MetadataNormalizer.first(tags, ['TDRC', 'TYER']));
    metadata.originalReleaseDate =
      MetadataNormalizer.parseDate(MetadataNormalizer.first(tags, ['TDOR', 'TORY']));
  }

  private static applyFlacTags(metadata: ParsedMetadata,
    tags: Map<string, Array<string>>): void {
    metadata.title = MetadataNormalizer.first(tags, ['TITLE']);
    metadata.sortTitle = MetadataNormalizer.first(tags, ['TITLESORT', 'TITLE_SORT']);
    metadata.album = MetadataNormalizer.first(tags, ['ALBUM']);
    metadata.albumArtists = MetadataNormalizer.values(tags, ['ALBUMARTIST', 'ALBUM ARTIST']);
    metadata.artists = MetadataNormalizer.values(tags, ['ARTIST']);
    metadata.composers = MetadataNormalizer.values(tags, ['COMPOSER']);
    metadata.lyricists = MetadataNormalizer.values(tags, ['LYRICIST', 'WRITER']);
    metadata.lyrics = MetadataNormalizer.first(tags, ['LYRICS', 'UNSYNCEDLYRICS']);
    metadata.conductors = MetadataNormalizer.values(tags, ['CONDUCTOR']);
    metadata.performers = MetadataNormalizer.values(tags, ['PERFORMER']);
    metadata.genres = MetadataNormalizer.values(tags, ['GENRE']);
    metadata.trackNumber =
      MetadataNormalizer.parseNumberPair(MetadataNormalizer.first(tags, ['TRACKNUMBER']));
    const trackTotal = MetadataNormalizer.first(tags, ['TRACKTOTAL', 'TOTALTRACKS']);
    if (metadata.trackNumber.total === undefined && trackTotal.length > 0) {
      metadata.trackNumber.total = MetadataNormalizer.parseNumberPair(trackTotal).value;
    }
    metadata.discNumber =
      MetadataNormalizer.parseNumberPair(MetadataNormalizer.first(tags, ['DISCNUMBER']));
    const discTotal = MetadataNormalizer.first(tags, ['DISCTOTAL', 'TOTALDISCS']);
    if (metadata.discNumber.total === undefined && discTotal.length > 0) {
      metadata.discNumber.total = MetadataNormalizer.parseNumberPair(discTotal).value;
    }
    metadata.releaseDate =
      MetadataNormalizer.parseDate(MetadataNormalizer.first(tags, ['DATE', 'YEAR']));
    metadata.originalReleaseDate = MetadataNormalizer.parseDate(
      MetadataNormalizer.first(tags, ['ORIGINALDATE', 'ORIGINALYEAR'])
    );
  }
}
