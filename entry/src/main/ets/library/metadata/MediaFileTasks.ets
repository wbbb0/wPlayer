import { taskpool } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  encodeArtworkWebP as encodeArtworkWebPNative,
  parseMediaFile as parseMediaFileNative,
  readArtworkBytes as readArtworkBytesNative
} from 'libwplayermedia.so';
import { MediaFormat, ParsedMetadata } from '../model/LibraryModels';
import { BinaryFileReader } from './BinaryFileReader';
import { NativeMediaMetadataAdapter } from './NativeMediaMetadataAdapter';

export interface MediaProbeResult {
  metadata: ParsedMetadata;
  fileName: string;
  fileSize: number;
  modifiedAt: number;
  quickFingerprint: string;
  workerDurationMs: number;
}

export interface MediaFileInspectionInput {
  uri: string;
  artworkSmallPath: string;
  artworkLargePath: string;
}

export interface MediaFileInspectionResult {
  available: boolean;
  fileSize: number;
  modifiedAt: number;
  artworkFilesAvailable: boolean;
}

@Concurrent
function inspectMediaFilesTask(
  inputs: Array<MediaFileInspectionInput>
): Array<MediaFileInspectionResult> {
  const results: Array<MediaFileInspectionResult> = [];
  for (let index = 0; index < inputs.length; index += 1) {
    const input = inputs[index];
    let file: fs.File | undefined;
    try {
      file = fs.openSync(input.uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      let artworkFilesAvailable = false;
      try {
        artworkFilesAvailable = input.artworkSmallPath.length > 0 &&
          input.artworkLargePath.length > 0 &&
          fs.accessSync(input.artworkSmallPath) &&
          fs.accessSync(input.artworkLargePath);
      } catch (_) {
        artworkFilesAvailable = false;
      }
      results.push({
        available: true,
        fileSize: stat.size,
        modifiedAt: stat.mtime,
        artworkFilesAvailable: artworkFilesAvailable
      });
    } catch (_) {
      results.push({
        available: false,
        fileSize: 0,
        modifiedAt: 0,
        artworkFilesAvailable: false
      });
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (_) {
        }
      }
    }
  }
  return results;
}

function errorMessage(error: Object): string {
  return error instanceof Error ? error.message : `${error}`;
}

function operationError(operation: string, error: Object): Error {
  return new Error(`${operation}: ${errorMessage(error)}`);
}

@Concurrent
function probeMediaFileTask(uri: string): MediaProbeResult {
  const startedAt = Date.now();
  try {
    const reader = new BinaryFileReader(uri);
    try {
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
      const digestResult = digest.digestSync();
      let quickHash = '';
      digestResult.data.forEach((value: number) => {
        quickHash += value.toString(16).padStart(2, '0');
      });
      const metadata = NativeMediaMetadataAdapter.fromNative(
        parseMediaFileNative(reader.fd, reader.size)
      );
      return {
        metadata: metadata,
        fileName: reader.name,
        fileSize: reader.size,
        modifiedAt: reader.modifiedAt,
        quickFingerprint: quickHash,
        workerDurationMs: Date.now() - startedAt
      };
    } finally {
      reader.close();
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`;
    throw new Error(`Unable to probe media file: ${message}`);
  }
}

@Concurrent
function calculateFullFingerprintTask(uri: string): string {
  let file: fs.File | undefined;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);
    const digest = cryptoFramework.createMd('SHA256');
    const buffer = new ArrayBuffer(Math.min(1024 * 1024, stat.size));
    let offset = 0;
    while (offset < stat.size) {
      const length = Math.min(buffer.byteLength, stat.size - offset);
      const bytesRead = fs.readSync(file.fd, buffer, { offset: offset, length: length });
      if (bytesRead <= 0) {
        throw new Error(`Unexpected end of file at ${offset}`);
      }
      digest.updateSync({ data: new Uint8Array(buffer, 0, bytesRead) });
      offset += bytesRead;
    }
    const result = digest.digestSync();
    let hexadecimal = '';
    result.data.forEach((value: number) => {
      hexadecimal += value.toString(16).padStart(2, '0');
    });
    return hexadecimal;
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`;
    throw new Error(`Unable to calculate full media fingerprint: ${message}`);
  } finally {
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (error) {
        const message = error instanceof Error ? error.message : `${error}`;
        console.warn(`Unable to close media file after fingerprinting: ${message}`);
      }
    }
  }
}

@Concurrent
function readEmbeddedLyricsTask(uri: string, format: MediaFormat): string {
  try {
    const reader = new BinaryFileReader(uri);
    try {
      const metadata = NativeMediaMetadataAdapter.fromNative(
        parseMediaFileNative(reader.fd, reader.size)
      );
      return metadata.format === format ? metadata.lyrics : '';
    } finally {
      reader.close();
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`;
    throw new Error(`Unable to read embedded lyrics: ${message}`);
  }
}

@Concurrent
function readArtworkBytesTask(uri: string, byteOffset: number, byteLength: number,
  payloadOffset: number, unsynchronized: boolean): ArrayBuffer {
  let file: fs.File | undefined;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);
    return readArtworkBytesNative(
      file.fd, stat.size, byteOffset, byteLength, payloadOffset, unsynchronized
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`;
    throw new Error(`Unable to read embedded artwork: ${message}`);
  } finally {
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (error) {
        const message = error instanceof Error ? error.message : `${error}`;
        console.warn(`Unable to close media file after reading artwork: ${message}`);
      }
    }
  }
}

@Concurrent
function readArtworkBytesFromFdTask(fd: number, byteOffset: number, byteLength: number,
  payloadOffset: number, unsynchronized: boolean): ArrayBuffer {
  try {
    const stat = fs.statSync(fd);
    return readArtworkBytesNative(
      fd, stat.size, byteOffset, byteLength, payloadOffset, unsynchronized
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : `${error}`;
    throw new Error(`Unable to read embedded artwork from authorized file: ${message}`);
  }
}

@Concurrent
function encodeArtworkWebPTask(bgraSourceBuffer: ArrayBuffer, width: number, height: number,
  premultiplied: boolean, quality: number, method: number, alphaQuality: number): ArrayBuffer {
  return encodeArtworkWebPNative(
    bgraSourceBuffer, width, height, premultiplied, quality, method, alphaQuality
  );
}

export function calculateFullFingerprint(uri: string): Promise<string> {
  try {
    return taskpool.execute(calculateFullFingerprintTask, uri) as Promise<string>;
  } catch (error) {
    return Promise.reject(operationError('Unable to submit full fingerprint task', error));
  }
}

export function probeMediaFile(uri: string): Promise<MediaProbeResult> {
  try {
    return taskpool.execute(probeMediaFileTask, uri) as Promise<MediaProbeResult>;
  } catch (error) {
    return Promise.reject(operationError('Unable to submit media probe task', error));
  }
}

export function inspectMediaFiles(
  inputs: Array<MediaFileInspectionInput>
): Promise<Array<MediaFileInspectionResult>> {
  try {
    return taskpool.execute(
      inspectMediaFilesTask, inputs
    ) as Promise<Array<MediaFileInspectionResult>>;
  } catch (error) {
    return Promise.reject(operationError('Unable to submit media inspection task', error));
  }
}

export function readEmbeddedLyrics(uri: string, format: MediaFormat): Promise<string> {
  try {
    return taskpool.execute(readEmbeddedLyricsTask, uri, format) as Promise<string>;
  } catch (error) {
    return Promise.reject(operationError('Unable to submit embedded lyrics task', error));
  }
}

export function readArtworkBytesAsync(uri: string, byteOffset: number, byteLength: number,
  payloadOffset: number, unsynchronized: boolean): Promise<ArrayBuffer> {
  try {
    return taskpool.execute(
      readArtworkBytesTask, uri, byteOffset, byteLength, payloadOffset, unsynchronized
    ) as Promise<ArrayBuffer>;
  } catch (error) {
    return Promise.reject(operationError('Unable to submit artwork read task', error));
  }
}

export async function readAuthorizedArtworkBytesAsync(
  uri: string,
  byteOffset: number,
  byteLength: number,
  payloadOffset: number,
  unsynchronized: boolean
): Promise<ArrayBuffer> {
  let file: fs.File | undefined;
  try {
    // Opening the Picker URI must happen in the application execution context
    // where its persisted authorization is available. The worker can then read
    // from the already-authorized process file descriptor.
    file = await fs.open(uri, fs.OpenMode.READ_ONLY);
    return await taskpool.execute(
      readArtworkBytesFromFdTask,
      file.fd,
      byteOffset,
      byteLength,
      payloadOffset,
      unsynchronized
    ) as ArrayBuffer;
  } catch (error) {
    return Promise.reject(operationError('Unable to read authorized artwork bytes', error));
  } finally {
    if (file !== undefined) {
      try {
        await fs.close(file);
      } catch (error) {
        console.warn(`Unable to close authorized artwork file: ${operationError('', error).message}`);
      }
    }
  }
}

export function encodeArtworkWebP(bgraSourceBuffer: ArrayBuffer, width: number, height: number,
  premultiplied: boolean, quality: number, method: number,
  alphaQuality: number): Promise<ArrayBuffer> {
  try {
    return taskpool.execute(
      encodeArtworkWebPTask,
      bgraSourceBuffer,
      width,
      height,
      premultiplied,
      quality,
      method,
      alphaQuality
    ) as Promise<ArrayBuffer>;
  } catch (error) {
    return Promise.reject(operationError('Unable to submit artwork WebP encoding task', error));
  }
}
