import { util } from '@kit.ArkTS';
import {
  ArtworkPictureType,
  MediaFormat,
  ParsedArtwork,
  ParsedMetadata
} from '../model/LibraryModels';
import { BinaryFileReader } from './BinaryFileReader';
import { MetadataFactory } from './MetadataFactory';
import { MetadataNormalizer } from './MetadataNormalizer';

export class FlacTagReader {
  private static readonly MAX_METADATA_BLOCK_BYTES: number = 32 * 1024 * 1024;
  private static readonly MAX_COMMENT_BYTES: number = 8 * 1024 * 1024;
  private static readonly MAX_COMMENT_COUNT: number = 4096;
  private static readonly MAX_ARTWORK_BYTES: number = 64 * 1024 * 1024;
  private static readonly MAX_BLOCK_COUNT: number = 256;
  private static readonly MAX_TOTAL_METADATA_BYTES: number = 64 * 1024 * 1024;
  private static readonly MAX_ARTWORK_COUNT: number = 32;

  static read(reader: BinaryFileReader): ParsedMetadata {
    const metadata = MetadataFactory.empty(MediaFormat.FLAC);
    const magic = reader.read(0, 4);
    if (magic[0] !== 0x66 || magic[1] !== 0x4C || magic[2] !== 0x61 || magic[3] !== 0x43) {
      throw new Error('Not a FLAC stream');
    }

    let offset = 4;
    let isLast = false;
    let artworkOrdinal = 0;
    let blockCount = 0;
    let totalMetadataBytes = 0;
    while (!isLast) {
      if (blockCount >= FlacTagReader.MAX_BLOCK_COUNT) {
        throw new Error('Too many FLAC metadata blocks');
      }
      const header = reader.read(offset, 4);
      isLast = (header[0] & 0x80) !== 0;
      const blockType = header[0] & 0x7F;
      const blockLength = BinaryFileReader.uint24BE(header, 1);
      const blockOffset = offset + 4;
      if (blockLength > FlacTagReader.MAX_METADATA_BLOCK_BYTES || blockOffset + blockLength > reader.size) {
        throw new Error(`Invalid FLAC metadata block: ${blockType}/${blockLength}`);
      }
      totalMetadataBytes += blockLength;
      if (totalMetadataBytes > FlacTagReader.MAX_TOTAL_METADATA_BYTES) {
        throw new Error('FLAC metadata exceeds the import budget');
      }
      if (blockType === 0 && blockLength >= 34) {
        FlacTagReader.readStreamInfo(reader.read(blockOffset, 34), metadata);
      } else if (blockType === 4 && blockLength <= FlacTagReader.MAX_COMMENT_BYTES) {
        FlacTagReader.readVorbisComments(reader.read(blockOffset, blockLength), metadata.rawTags);
      } else if (blockType === 6 && artworkOrdinal < FlacTagReader.MAX_ARTWORK_COUNT) {
        const artwork = FlacTagReader.readPicture(reader, blockOffset, blockLength, artworkOrdinal);
        if (artwork !== undefined) {
          metadata.artworks.push(artwork);
          artworkOrdinal += 1;
        }
      }
      offset = blockOffset + blockLength;
      blockCount += 1;
    }

    FlacTagReader.applyTags(metadata);
    return metadata;
  }

  private static readStreamInfo(bytes: Uint8Array, metadata: ParsedMetadata): void {
    const packedHigh = BinaryFileReader.uint32BE(bytes, 10);
    const packedLow = BinaryFileReader.uint32BE(bytes, 14);
    metadata.sampleRate = Math.floor(packedHigh / 0x1000);
    metadata.channelCount = ((packedHigh >> 9) & 0x07) + 1;
    metadata.bitsPerSample = ((packedHigh >> 4) & 0x1F) + 1;
    const totalSamplesHigh = packedHigh & 0x0F;
    const totalSamples = totalSamplesHigh * 0x100000000 + packedLow;
    if (metadata.sampleRate > 0) {
      metadata.durationMs = Math.round(totalSamples * 1000 / metadata.sampleRate);
    }
  }

  private static readVorbisComments(bytes: Uint8Array, tags: Map<string, Array<string>>): void {
    let offset = 0;
    if (bytes.length < 8) {
      return;
    }
    const vendorLength = BinaryFileReader.uint32LE(bytes, offset);
    offset += 4 + vendorLength;
    if (offset + 4 > bytes.length) {
      return;
    }
    const commentCount = Math.min(BinaryFileReader.uint32LE(bytes, offset), FlacTagReader.MAX_COMMENT_COUNT);
    offset += 4;
    const decoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
    for (let index = 0; index < commentCount && offset + 4 <= bytes.length; index += 1) {
      const commentLength = BinaryFileReader.uint32LE(bytes, offset);
      offset += 4;
      if (commentLength < 0 || offset + commentLength > bytes.length) {
        break;
      }
      const comment = decoder.decodeToString(bytes.subarray(offset, offset + commentLength));
      offset += commentLength;
      const separator = comment.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      const key = comment.substring(0, separator).trim().toUpperCase();
      const value = comment.substring(separator + 1).trim();
      if (key.length === 0 || value.length === 0) {
        continue;
      }
      const values = tags.get(key) ?? [];
      values.push(value);
      tags.set(key, values);
    }
  }

  private static readPicture(reader: BinaryFileReader, blockOffset: number, blockLength: number,
    ordinal: number): ParsedArtwork | undefined {
    if (blockLength < 32) {
      return undefined;
    }
    const bytes = reader.read(blockOffset, blockLength);
    let offset = 0;
    const pictureType = BinaryFileReader.uint32BE(bytes, offset);
    offset += 4;
    const mimeLength = BinaryFileReader.uint32BE(bytes, offset);
    offset += 4;
    if (mimeLength > 256 || offset + mimeLength + 4 > bytes.length) {
      return undefined;
    }
    const decoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
    const mimeType = decoder.decodeToString(bytes.subarray(offset, offset + mimeLength));
    offset += mimeLength;
    const descriptionLength = BinaryFileReader.uint32BE(bytes, offset);
    offset += 4;
    if (descriptionLength > 64 * 1024 || offset + descriptionLength + 20 > bytes.length) {
      return undefined;
    }
    const description = decoder.decodeToString(bytes.subarray(offset, offset + descriptionLength));
    offset += descriptionLength;
    const width = BinaryFileReader.uint32BE(bytes, offset);
    const height = BinaryFileReader.uint32BE(bytes, offset + 4);
    const colorDepth = BinaryFileReader.uint32BE(bytes, offset + 8);
    offset += 16;
    const dataLength = BinaryFileReader.uint32BE(bytes, offset);
    offset += 4;
    if (dataLength <= 0 || dataLength > FlacTagReader.MAX_ARTWORK_BYTES || offset + dataLength > bytes.length) {
      return undefined;
    }
    return {
      pictureType: pictureType <= ArtworkPictureType.PUBLISHER_LOGO ?
        pictureType as ArtworkPictureType : ArtworkPictureType.OTHER,
      mimeType: mimeType,
      description: description,
      width: width,
      height: height,
      colorDepth: colorDepth,
      byteOffset: blockOffset + offset,
      byteLength: dataLength,
      payloadOffset: 0,
      ordinal: ordinal,
      unsynchronized: false
    };
  }

  private static applyTags(metadata: ParsedMetadata): void {
    const tags = metadata.rawTags;
    metadata.title = MetadataNormalizer.first(tags, ['TITLE']);
    metadata.sortTitle = MetadataNormalizer.first(tags, ['TITLESORT', 'TITLE_SORT']);
    metadata.album = MetadataNormalizer.first(tags, ['ALBUM']);
    metadata.albumArtists = MetadataNormalizer.values(tags, ['ALBUMARTIST', 'ALBUM ARTIST']);
    metadata.artists = MetadataNormalizer.values(tags, ['ARTIST']);
    metadata.composers = MetadataNormalizer.values(tags, ['COMPOSER']);
    metadata.lyricists = MetadataNormalizer.values(tags, ['LYRICIST', 'WRITER']);
    metadata.conductors = MetadataNormalizer.values(tags, ['CONDUCTOR']);
    metadata.performers = MetadataNormalizer.values(tags, ['PERFORMER']);
    metadata.genres = MetadataNormalizer.values(tags, ['GENRE']);
    metadata.trackNumber = MetadataNormalizer.parseNumberPair(MetadataNormalizer.first(tags, ['TRACKNUMBER']));
    const trackTotal = MetadataNormalizer.first(tags, ['TRACKTOTAL', 'TOTALTRACKS']);
    if (metadata.trackNumber.total === undefined && trackTotal.length > 0) {
      metadata.trackNumber.total = MetadataNormalizer.parseNumberPair(trackTotal).value;
    }
    metadata.discNumber = MetadataNormalizer.parseNumberPair(MetadataNormalizer.first(tags, ['DISCNUMBER']));
    const discTotal = MetadataNormalizer.first(tags, ['DISCTOTAL', 'TOTALDISCS']);
    if (metadata.discNumber.total === undefined && discTotal.length > 0) {
      metadata.discNumber.total = MetadataNormalizer.parseNumberPair(discTotal).value;
    }
    metadata.releaseDate = MetadataNormalizer.parseDate(MetadataNormalizer.first(tags, ['DATE', 'YEAR']));
    metadata.originalReleaseDate = MetadataNormalizer.parseDate(
      MetadataNormalizer.first(tags, ['ORIGINALDATE', 'ORIGINALYEAR'])
    );
  }
}
