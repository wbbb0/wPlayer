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

interface Id3Frame {
  id: string;
  dataOffset: number;
  dataLength: number;
  unsynchronized: boolean;
}

export class Id3TagReader {
  private static readonly MAX_TAG_BYTES: number = 32 * 1024 * 1024;
  private static readonly MAX_FRAME_BYTES: number = 16 * 1024 * 1024;
  private static readonly MAX_ARTWORK_BYTES: number = 64 * 1024 * 1024;
  private static readonly MAX_FRAME_COUNT: number = 8192;
  private static readonly MAX_ARTWORK_COUNT: number = 32;

  static read(reader: BinaryFileReader): ParsedMetadata {
    const metadata = MetadataFactory.empty(MediaFormat.MP3);
    if (reader.size < 10) {
      return metadata;
    }
    const header = reader.read(0, 10);
    if (header[0] !== 0x49 || header[1] !== 0x44 || header[2] !== 0x33) {
      Id3TagReader.readId3v1(reader, metadata.rawTags);
      Id3TagReader.applyTags(metadata);
      return metadata;
    }
    const version = header[3];
    if (version < 2 || version > 4) {
      return metadata;
    }
    const tagSize = BinaryFileReader.syncSafe32(header, 6);
    if (tagSize <= 0 || tagSize > Id3TagReader.MAX_TAG_BYTES || 10 + tagSize > reader.size) {
      throw new Error(`Invalid ID3 tag size: ${tagSize}`);
    }
    const globalUnsynchronization = (header[5] & 0x80) !== 0;
    let frameOffset = 10;
    const tagEnd = 10 + tagSize;
    if ((header[5] & 0x40) !== 0 && version >= 3) {
      const extendedHeader = reader.read(frameOffset, 4);
      const extendedSize = version === 4 ?
        BinaryFileReader.syncSafe32(extendedHeader, 0) : BinaryFileReader.uint32BE(extendedHeader, 0) + 4;
      if (extendedSize >= 4 && frameOffset + extendedSize <= tagEnd) {
        frameOffset += extendedSize;
      }
    }

    let frameCount = 0;
    let artworkOrdinal = 0;
    while (frameOffset < tagEnd && frameCount < Id3TagReader.MAX_FRAME_COUNT) {
      const frame = Id3TagReader.readFrameHeader(reader, frameOffset, tagEnd, version, globalUnsynchronization);
      if (frame === undefined) {
        break;
      }
      if (frame.dataLength <= Id3TagReader.MAX_FRAME_BYTES) {
        if ((frame.id === 'APIC' || frame.id === 'PIC') && artworkOrdinal < Id3TagReader.MAX_ARTWORK_COUNT) {
          const artwork = Id3TagReader.readPicture(reader, frame, version, artworkOrdinal);
          if (artwork !== undefined) {
            metadata.artworks.push(artwork);
            artworkOrdinal += 1;
          }
        } else if (frame.id.startsWith('T') && frame.id !== 'TXXX') {
          Id3TagReader.addTextFrame(reader, frame, metadata.rawTags);
        }
      }
      frameOffset = frame.dataOffset + frame.dataLength;
      frameCount += 1;
    }
    Id3TagReader.readId3v1(reader, metadata.rawTags);
    Id3TagReader.applyTags(metadata);
    return metadata;
  }

  static readArtworkBytes(reader: BinaryFileReader, artwork: ParsedArtwork): Uint8Array {
    const bytes = reader.read(artwork.byteOffset, artwork.byteLength);
    if (!artwork.unsynchronized) {
      return bytes;
    }
    return Id3TagReader.removeUnsynchronization(bytes).subarray(artwork.payloadOffset);
  }

  private static readFrameHeader(reader: BinaryFileReader, offset: number, tagEnd: number,
    version: number, globalUnsynchronization: boolean): Id3Frame | undefined {
    const headerSize = version === 2 ? 6 : 10;
    if (offset + headerSize > tagEnd) {
      return undefined;
    }
    const bytes = reader.read(offset, headerSize);
    const idLength = version === 2 ? 3 : 4;
    let id = '';
    for (let index = 0; index < idLength; index += 1) {
      const value = bytes[index];
      if (value === 0) {
        return undefined;
      }
      id += String.fromCharCode(value);
    }
    const frameSize = version === 2 ? BinaryFileReader.uint24BE(bytes, 3) :
      (version === 4 ? BinaryFileReader.syncSafe32(bytes, 4) : BinaryFileReader.uint32BE(bytes, 4));
    if (frameSize <= 0 || offset + headerSize + frameSize > tagEnd) {
      return undefined;
    }
    const formatFlags = version === 2 ? 0 : bytes[9];
    const unsupported = version === 3 ? (formatFlags & 0xC0) !== 0 : (formatFlags & 0x0C) !== 0;
    if (unsupported) {
      return {
        id: '',
        dataOffset: offset + headerSize,
        dataLength: frameSize,
        unsynchronized: false
      };
    }
    let prefixLength = 0;
    if (version === 3 && (formatFlags & 0x20) !== 0) {
      prefixLength += 1;
    } else if (version === 4) {
      if ((formatFlags & 0x40) !== 0) {
        prefixLength += 1;
      }
      if ((formatFlags & 0x01) !== 0) {
        prefixLength += 4;
      }
    }
    if (prefixLength >= frameSize) {
      return undefined;
    }
    return {
      id: version === 2 ? Id3TagReader.mapV22FrameId(id) : id,
      dataOffset: offset + headerSize + prefixLength,
      dataLength: frameSize - prefixLength,
      unsynchronized: globalUnsynchronization || (version === 4 && (formatFlags & 0x02) !== 0)
    };
  }

  private static addTextFrame(reader: BinaryFileReader, frame: Id3Frame,
    tags: Map<string, Array<string>>): void {
    let bytes = reader.read(frame.dataOffset, frame.dataLength);
    if (frame.unsynchronized) {
      bytes = Id3TagReader.removeUnsynchronization(bytes);
    }
    if (bytes.length < 2) {
      return;
    }
    const text = Id3TagReader.decodeText(bytes[0], bytes.subarray(1)).replace(/\u0000+$/g, '');
    const values = text.split('\u0000').map((value: string) => value.trim())
      .filter((value: string) => value.length > 0);
    if (values.length === 0) {
      return;
    }
    const existing = tags.get(frame.id) ?? [];
    existing.push(...values);
    tags.set(frame.id, existing);
  }

  private static readPicture(reader: BinaryFileReader, frame: Id3Frame, version: number,
    ordinal: number): ParsedArtwork | undefined {
    let bytes = reader.read(frame.dataOffset, frame.dataLength);
    if (frame.unsynchronized) {
      bytes = Id3TagReader.removeUnsynchronization(bytes);
    }
    if (bytes.length < 8) {
      return undefined;
    }
    const encoding = bytes[0];
    let offset = 1;
    let mimeType = '';
    if (version === 2) {
      mimeType = Id3TagReader.decodeLatin1(bytes.subarray(offset, offset + 3));
      mimeType = mimeType.toUpperCase() === 'PNG' ? 'image/png' : 'image/jpeg';
      offset += 3;
    } else {
      const mimeEnd = Id3TagReader.findTerminator(bytes, offset, 1);
      if (mimeEnd < 0) {
        return undefined;
      }
      mimeType = Id3TagReader.decodeLatin1(bytes.subarray(offset, mimeEnd));
      offset = mimeEnd + 1;
      if (mimeType === '-->') {
        return undefined;
      }
    }
    if (offset >= bytes.length) {
      return undefined;
    }
    const pictureType = bytes[offset];
    offset += 1;
    const terminatorLength = encoding === 1 || encoding === 2 ? 2 : 1;
    const descriptionEnd = Id3TagReader.findTerminator(bytes, offset, terminatorLength);
    if (descriptionEnd < 0) {
      return undefined;
    }
    const description = Id3TagReader.decodeText(encoding, bytes.subarray(offset, descriptionEnd));
    offset = descriptionEnd + terminatorLength;
    const imageLength = bytes.length - offset;
    if (imageLength <= 0 || imageLength > Id3TagReader.MAX_ARTWORK_BYTES) {
      return undefined;
    }
    return {
      pictureType: pictureType <= ArtworkPictureType.PUBLISHER_LOGO ?
        pictureType as ArtworkPictureType : ArtworkPictureType.OTHER,
      mimeType: mimeType,
      description: description,
      width: 0,
      height: 0,
      colorDepth: 0,
      byteOffset: frame.unsynchronized ? frame.dataOffset : frame.dataOffset + offset,
      byteLength: frame.unsynchronized ? frame.dataLength : imageLength,
      payloadOffset: frame.unsynchronized ? offset : 0,
      ordinal: ordinal,
      unsynchronized: frame.unsynchronized
    };
  }

  private static readId3v1(reader: BinaryFileReader, tags: Map<string, Array<string>>): void {
    if (reader.size < 128) {
      return;
    }
    const bytes = reader.read(reader.size - 128, 128);
    if (bytes[0] !== 0x54 || bytes[1] !== 0x41 || bytes[2] !== 0x47) {
      return;
    }
    Id3TagReader.addFallbackTag(tags, 'TIT2', Id3TagReader.decodeLatin1(bytes.subarray(3, 33)));
    Id3TagReader.addFallbackTag(tags, 'TPE1', Id3TagReader.decodeLatin1(bytes.subarray(33, 63)));
    Id3TagReader.addFallbackTag(tags, 'TALB', Id3TagReader.decodeLatin1(bytes.subarray(63, 93)));
    Id3TagReader.addFallbackTag(tags, 'TDRC', Id3TagReader.decodeLatin1(bytes.subarray(93, 97)));
    if (bytes[125] === 0 && bytes[126] > 0) {
      Id3TagReader.addFallbackTag(tags, 'TRCK', `${bytes[126]}`);
    }
  }

  private static addFallbackTag(tags: Map<string, Array<string>>, key: string, value: string): void {
    if (!tags.has(key) && value.trim().length > 0) {
      tags.set(key, [value.trim()]);
    }
  }

  private static decodeText(encoding: number, bytes: Uint8Array): string {
    if (bytes.length === 0) {
      return '';
    }
    if (encoding === 0) {
      return Id3TagReader.decodeLatin1(bytes);
    }
    if (encoding === 2) {
      return util.TextDecoder.create('utf-16be', { fatal: false, ignoreBOM: true }).decodeToString(bytes);
    }
    if (encoding === 1) {
      return util.TextDecoder.create('utf-16', { fatal: false, ignoreBOM: false }).decodeToString(bytes);
    }
    return util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true }).decodeToString(bytes);
  }

  private static decodeLatin1(bytes: Uint8Array): string {
    let value = '';
    for (let index = 0; index < bytes.length; index += 1) {
      if (bytes[index] === 0) {
        break;
      }
      value += String.fromCharCode(bytes[index]);
    }
    return value.trim();
  }

  private static findTerminator(bytes: Uint8Array, start: number, length: number): number {
    for (let index = start; index + length <= bytes.length; index += length) {
      if (bytes[index] === 0 && (length === 1 || bytes[index + 1] === 0)) {
        return index;
      }
    }
    return -1;
  }

  private static removeUnsynchronization(bytes: Uint8Array): Uint8Array {
    const output = new Uint8Array(bytes.length);
    let outputLength = 0;
    for (let index = 0; index < bytes.length; index += 1) {
      output[outputLength] = bytes[index];
      outputLength += 1;
      if (bytes[index] === 0xFF && index + 1 < bytes.length && bytes[index + 1] === 0x00) {
        index += 1;
      }
    }
    return output.subarray(0, outputLength);
  }

  private static mapV22FrameId(id: string): string {
    const mappings: Map<string, string> = new Map<string, string>([
      ['TT2', 'TIT2'], ['TAL', 'TALB'], ['TP1', 'TPE1'], ['TP2', 'TPE2'],
      ['TCM', 'TCOM'], ['TXT', 'TEXT'], ['TCO', 'TCON'], ['TRK', 'TRCK'],
      ['TPA', 'TPOS'], ['TYE', 'TYER'], ['TOR', 'TORY'], ['PIC', 'PIC']
    ]);
    return mappings.get(id) ?? id;
  }

  private static applyTags(metadata: ParsedMetadata): void {
    const tags = metadata.rawTags;
    metadata.title = MetadataNormalizer.first(tags, ['TIT2']);
    metadata.sortTitle = MetadataNormalizer.first(tags, ['TSOT']);
    metadata.album = MetadataNormalizer.first(tags, ['TALB']);
    metadata.albumArtists = MetadataNormalizer.values(tags, ['TPE2']);
    metadata.artists = MetadataNormalizer.values(tags, ['TPE1']);
    metadata.composers = MetadataNormalizer.values(tags, ['TCOM']);
    metadata.lyricists = MetadataNormalizer.values(tags, ['TEXT']);
    metadata.conductors = MetadataNormalizer.values(tags, ['TPE3']);
    metadata.performers = MetadataNormalizer.values(tags, ['TPE4']);
    metadata.genres = MetadataNormalizer.values(tags, ['TCON']);
    metadata.trackNumber = MetadataNormalizer.parseNumberPair(MetadataNormalizer.first(tags, ['TRCK']));
    metadata.discNumber = MetadataNormalizer.parseNumberPair(MetadataNormalizer.first(tags, ['TPOS']));
    metadata.releaseDate = MetadataNormalizer.parseDate(MetadataNormalizer.first(tags, ['TDRC', 'TYER']));
    metadata.originalReleaseDate = MetadataNormalizer.parseDate(MetadataNormalizer.first(tags, ['TDOR', 'TORY']));
  }
}
