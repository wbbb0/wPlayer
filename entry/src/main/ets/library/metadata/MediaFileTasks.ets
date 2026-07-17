import { taskpool } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { MediaFormat, ParsedMetadata } from '../model/LibraryModels';
import { BinaryFileReader } from './BinaryFileReader';
import { FlacTagReader } from './FlacTagReader';
import { Id3TagReader } from './Id3TagReader';

export interface MediaProbeResult {
  metadata: ParsedMetadata;
  fileName: string;
  fileSize: number;
  modifiedAt: number;
  quickFingerprint: string;
  workerDurationMs: number;
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
      const signature = reader.read(0, Math.min(4, reader.size));
      let metadata: ParsedMetadata;
      if (signature.length >= 4 && signature[0] === 0x66 && signature[1] === 0x4C &&
        signature[2] === 0x61 && signature[3] === 0x43) {
        metadata = FlacTagReader.read(reader);
      } else if ((signature.length >= 3 && signature[0] === 0x49 && signature[1] === 0x44 &&
        signature[2] === 0x33) ||
        (signature.length >= 2 && signature[0] === 0xFF && (signature[1] & 0xE0) === 0xE0)) {
        metadata = Id3TagReader.read(reader);
      } else {
        throw new Error('Only MP3 and FLAC files are supported');
      }
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
    let offset = 0;
    while (offset < stat.size) {
      const length = Math.min(1024 * 1024, stat.size - offset);
      const buffer = new ArrayBuffer(length);
      const bytesRead = fs.readSync(file.fd, buffer, { offset: offset, length: length });
      if (bytesRead <= 0) {
        throw new Error(`Unexpected end of file at ${offset}`);
      }
      digest.updateSync({ data: bytesRead === length ? new Uint8Array(buffer) : new Uint8Array(buffer, 0, bytesRead) });
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
      if (format === MediaFormat.MP3) {
        return Id3TagReader.read(reader).lyrics;
      }
      if (format === MediaFormat.FLAC) {
        return FlacTagReader.read(reader).lyrics;
      }
      return '';
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
  if (byteOffset < 0 || byteLength <= 0 || byteLength > 64 * 1024 * 1024) {
    throw new Error(`Invalid artwork byte range: ${byteOffset}+${byteLength}`);
  }
  let file: fs.File | undefined;
  try {
    file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);
    if (byteOffset + byteLength > stat.size) {
      throw new Error(`Artwork byte range exceeds file: ${byteOffset}+${byteLength}/${stat.size}`);
    }
    const buffer = new ArrayBuffer(byteLength);
    let totalRead = 0;
    while (totalRead < byteLength) {
      const bytesRead = fs.readSync(file.fd, buffer, {
        offset: byteOffset + totalRead,
        length: byteLength - totalRead
      });
      if (bytesRead <= 0) {
        throw new Error(`Unexpected end of artwork at ${byteOffset + totalRead}`);
      }
      totalRead += bytesRead;
    }
    if (!unsynchronized) {
      return buffer;
    }
    const source = new Uint8Array(buffer);
    const output = new Uint8Array(source.length);
    let outputLength = 0;
    for (let index = 0; index < source.length; index += 1) {
      output[outputLength++] = source[index];
      if (source[index] === 0xFF && index + 1 < source.length && source[index + 1] === 0x00) {
        index += 1;
      }
    }
    if (payloadOffset < 0 || payloadOffset > outputLength) {
      throw new Error(`Invalid artwork payload offset: ${payloadOffset}/${outputLength}`);
    }
    return output.buffer.slice(payloadOffset, outputLength);
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
function flattenArtworkPixelsTask(sourceBuffer: ArrayBuffer, width: number, height: number,
  premultiplied: boolean): ArrayBuffer {
  const source = new Uint8Array(sourceBuffer);
  const opaque = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const sourceOffset = (y * width + x) * 4;
      const targetOffset = sourceOffset;
      const alpha = source[sourceOffset + 3];
      const white = 255 - alpha;
      for (let channel = 0; channel < 3; channel += 1) {
        // readPixels(PositionArea) returns BGRA; emit RGBA for ImagePacker.
        const sourceChannel = channel === 0 ? 2 : channel === 2 ? 0 : 1;
        const color = source[sourceOffset + sourceChannel];
        opaque[targetOffset + channel] = premultiplied ?
          Math.min(255, color + white) : Math.round((color * alpha) / 255 + white);
      }
      opaque[targetOffset + 3] = 255;
    }
  }
  return opaque.buffer;
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

export function flattenArtworkPixels(sourceBuffer: ArrayBuffer, width: number, height: number,
  premultiplied: boolean): Promise<ArrayBuffer> {
  try {
    return taskpool.execute(
      flattenArtworkPixelsTask, sourceBuffer, width, height, premultiplied
    ) as Promise<ArrayBuffer>;
  } catch (error) {
    return Promise.reject(operationError('Unable to submit artwork flattening task', error));
  }
}
