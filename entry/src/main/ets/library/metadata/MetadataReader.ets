import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import {
  MediaFormat,
  MetadataReadResult,
  ParsedMetadata
} from '../model/LibraryModels';
import { MetadataFactory } from './MetadataFactory';
import { MetadataNormalizer } from './MetadataNormalizer';
import { probeMediaFile, readEmbeddedLyrics } from './MediaFileTasks';
import { ImportPerformanceTrace } from '../importer/ImportPerformanceTrace';

export class MetadataReader {
  static async readLyrics(uri: string, fileSize: number, format: MediaFormat): Promise<string> {
    const parsedLyrics = await readEmbeddedLyrics(uri, format);
    if (parsedLyrics.length > 0) {
      return parsedLyrics;
    }
    const empty = MetadataFactory.empty(format);
    const metadata = await MetadataReader.mergeSystemMetadata(uri, fileSize, empty);
    return metadata.lyrics;
  }
  static async read(uri: string): Promise<MetadataReadResult> {
    const fileId = ImportPerformanceTrace.fileId(uri);
    const probeStartedAt = Date.now();
    const probe = await probeMediaFile(uri);
    ImportPerformanceTrace.mark('probe_total', probeStartedAt, fileId,
      `worker_ms=${probe.workerDurationMs} queue_ms=${Math.max(0, Date.now() - probeStartedAt - probe.workerDurationMs)}` +
      ` bytes=${probe.fileSize}`);
    let metadata = probe.metadata;
    if (MetadataReader.needsSystemMetadata(metadata)) {
      const systemMetadataStartedAt = Date.now();
      metadata = await MetadataReader.mergeSystemMetadata(uri, probe.fileSize, metadata);
      ImportPerformanceTrace.mark('system_metadata', systemMetadataStartedAt, fileId);
    } else {
      ImportPerformanceTrace.event('system_metadata_skipped', fileId, 'reason=parsed_fields_complete');
    }
    if (metadata.title.length === 0) {
      metadata.title = MetadataReader.fileStem(probe.fileName);
    }
    if (metadata.sortTitle.length === 0) {
      metadata.sortTitle = metadata.title;
    }
    return {
      metadata: metadata,
      fileName: probe.fileName,
      fileSize: probe.fileSize,
      modifiedAt: probe.modifiedAt,
      quickFingerprint: probe.quickFingerprint,
      fullFingerprint: ''
    };
  }

  private static needsSystemMetadata(metadata: ParsedMetadata): boolean {
    return metadata.durationMs <= 0 || metadata.sampleRate <= 0 ||
      metadata.channelCount <= 0 || metadata.mimeType.length === 0;
  }

  private static async mergeSystemMetadata(uri: string, fileSize: number,
    parsed: ParsedMetadata): Promise<ParsedMetadata> {
    let file: fs.File | undefined;
    let extractor: media.AVMetadataExtractor | undefined;
    try {
      file = await fs.open(uri, fs.OpenMode.READ_ONLY);
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
      if (parsed.lyrics.length === 0 && systemMetadata.customInfo !== undefined) {
        parsed.lyrics = MetadataReader.customLyrics(systemMetadata.customInfo);
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
      if (file !== undefined) {
        try {
          await fs.close(file);
        } catch (error) {
          console.warn(`Metadata file close failed: ${MetadataReader.errorMessage(error)}`);
        }
      }
    }
    return parsed;
  }

  private static customLyrics(customInfo: Record<string, string>): string {
    const keys = ['lyrics', 'LYRICS', '©lyr', '\u00A9lyr'];
    for (let index = 0; index < keys.length; index += 1) {
      const value = customInfo[keys[index]];
      if (value !== undefined && value.trim().length > 0) {
        return value.trim();
      }
    }
    return '';
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
