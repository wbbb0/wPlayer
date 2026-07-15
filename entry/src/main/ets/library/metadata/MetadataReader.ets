import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { media } from '@kit.MediaKit';
import {
  MediaFormat,
  MetadataReadResult,
  ParsedArtwork,
  ParsedMetadata
} from '../model/LibraryModels';
import { BinaryFileReader } from './BinaryFileReader';
import { FlacTagReader } from './FlacTagReader';
import { Id3TagReader } from './Id3TagReader';
import { MetadataNormalizer } from './MetadataNormalizer';
import { calculateFullFingerprint } from './MediaFileTasks';

export class MetadataReader {
  static async read(uri: string): Promise<MetadataReadResult> {
    const reader = new BinaryFileReader(uri);
    let metadata: ParsedMetadata;
    let fileName = reader.name;
    const fileSize = reader.size;
    const modifiedAt = reader.modifiedAt;
    let quickFingerprint = '';
    try {
      quickFingerprint = MetadataReader.quickFingerprint(reader);
      const signature = reader.read(0, Math.min(4, reader.size));
      if (signature.length >= 4 && signature[0] === 0x66 && signature[1] === 0x4C &&
        signature[2] === 0x61 && signature[3] === 0x43) {
        metadata = FlacTagReader.read(reader);
      } else if ((signature.length >= 3 && signature[0] === 0x49 && signature[1] === 0x44 && signature[2] === 0x33) ||
        MetadataReader.looksLikeMp3(signature)) {
        metadata = Id3TagReader.read(reader);
      } else {
        throw new Error('Only MP3 and FLAC files are supported');
      }
    } finally {
      reader.close();
    }
    const fullFingerprintPromise = calculateFullFingerprint(uri);
    metadata = await MetadataReader.mergeSystemMetadata(uri, fileSize, metadata);
    if (metadata.title.length === 0) {
      metadata.title = MetadataReader.fileStem(fileName);
    }
    if (metadata.sortTitle.length === 0) {
      metadata.sortTitle = metadata.title;
    }
    return {
      metadata: metadata,
      fileName: fileName,
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      quickFingerprint: quickFingerprint,
      fullFingerprint: await fullFingerprintPromise
    };
  }

  static readArtworkBytes(uri: string, metadata: ParsedMetadata, artworkIndex: number): Uint8Array {
    const artwork = metadata.artworks[artworkIndex];
    if (artwork === undefined) {
      throw new Error(`Artwork index out of range: ${artworkIndex}`);
    }
    const reader = new BinaryFileReader(uri);
    try {
      if (metadata.format === MediaFormat.MP3) {
        return Id3TagReader.readArtworkBytes(reader, artwork);
      }
      return reader.read(artwork.byteOffset, artwork.byteLength);
    } finally {
      reader.close();
    }
  }

  static readSelectedArtworkBytes(uri: string, format: MediaFormat, artwork: ParsedArtwork): Uint8Array {
    const reader = new BinaryFileReader(uri);
    try {
      if (format === MediaFormat.MP3) {
        return Id3TagReader.readArtworkBytes(reader, artwork);
      }
      return reader.read(artwork.byteOffset, artwork.byteLength);
    } finally {
      reader.close();
    }
  }

  private static async mergeSystemMetadata(uri: string, fileSize: number,
    parsed: ParsedMetadata): Promise<ParsedMetadata> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let extractor: media.AVMetadataExtractor | undefined;
    try {
      extractor = await media.createAVMetadataExtractor();
      extractor.fdSrc = { fd: file.fd, offset: 0, length: fileSize };
      const systemMetadata = await extractor.fetchMetadata();
      parsed.title = parsed.title.length > 0 ? parsed.title : (systemMetadata.title ?? '');
      parsed.album = parsed.album.length > 0 ? parsed.album : (systemMetadata.album ?? '');
      if (parsed.artists.length === 0 && systemMetadata.artist !== undefined) {
        parsed.artists = MetadataNormalizer.splitValues([systemMetadata.artist]);
      }
      if (parsed.albumArtists.length === 0 && systemMetadata.albumArtist !== undefined) {
        parsed.albumArtists = MetadataNormalizer.splitValues([systemMetadata.albumArtist]);
      }
      if (parsed.composers.length === 0 && systemMetadata.composer !== undefined) {
        parsed.composers = MetadataNormalizer.splitValues([systemMetadata.composer]);
      }
      if (parsed.genres.length === 0 && systemMetadata.genre !== undefined) {
        parsed.genres = MetadataNormalizer.splitValues([systemMetadata.genre]);
      }
      if (parsed.releaseDate.precision === 0 && systemMetadata.dateTime !== undefined) {
        parsed.releaseDate = MetadataNormalizer.parseDate(systemMetadata.dateTime);
      }
      parsed.durationMs = parsed.durationMs > 0 ? parsed.durationMs : MetadataReader.parseNumber(systemMetadata.duration);
      parsed.sampleRate = parsed.sampleRate > 0 ? parsed.sampleRate : MetadataReader.parseNumber(systemMetadata.sampleRate);
      parsed.mimeType = systemMetadata.mimeType ?? parsed.mimeType;
    } catch (error) {
      console.warn(`System metadata fallback unavailable: ${MetadataReader.errorMessage(error)}`);
    } finally {
      if (extractor !== undefined) {
        try {
          await extractor.release();
        } catch (error) {
          console.warn(`Metadata extractor release failed: ${MetadataReader.errorMessage(error)}`);
        }
      }
      fs.closeSync(file);
    }
    return parsed;
  }

  private static looksLikeMp3(signature: Uint8Array): boolean {
    return signature.length >= 2 && signature[0] === 0xFF && (signature[1] & 0xE0) === 0xE0;
  }

  private static quickFingerprint(reader: BinaryFileReader): string {
    const chunkSize = Math.min(64 * 1024, reader.size);
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: reader.read(0, chunkSize) });
    if (reader.size > chunkSize) {
      digest.updateSync({ data: reader.read(reader.size - chunkSize, chunkSize) });
    }
    const sizeBytes = new Uint8Array(8);
    let remainingSize = reader.size;
    for (let index = 7; index >= 0; index -= 1) {
      sizeBytes[index] = remainingSize & 0xFF;
      remainingSize = Math.floor(remainingSize / 256);
    }
    digest.updateSync({ data: sizeBytes });
    const result = digest.digestSync();
    let hexadecimal = '';
    result.data.forEach((value: number) => {
      hexadecimal += value.toString(16).padStart(2, '0');
    });
    return hexadecimal;
  }

  private static fileStem(fileName: string): string {
    const lastDot = fileName.lastIndexOf('.');
    return lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
  }

  private static parseNumber(value: string | undefined): number {
    if (value === undefined) {
      return 0;
    }
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  private static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
