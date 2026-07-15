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

@Concurrent
function probeMediaFileTask(uri: string): MediaProbeResult {
  const startedAt = Date.now();
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
}

@Concurrent
function calculateFullFingerprintTask(uri: string): string {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
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
  } finally {
    fs.closeSync(file);
  }
}

@Concurrent
function readArtworkBytesTask(uri: string, byteOffset: number, byteLength: number,
  payloadOffset: number, unsynchronized: boolean): ArrayBuffer {
  if (byteOffset < 0 || byteLength <= 0 || byteLength > 64 * 1024 * 1024) {
    throw new Error(`Invalid artwork byte range: ${byteOffset}+${byteLength}`);
  }
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
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
  } finally {
    fs.closeSync(file);
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
  return taskpool.execute(calculateFullFingerprintTask, uri) as Promise<string>;
}

export function probeMediaFile(uri: string): Promise<MediaProbeResult> {
  return taskpool.execute(probeMediaFileTask, uri) as Promise<MediaProbeResult>;
}

export function readArtworkBytesAsync(uri: string, byteOffset: number, byteLength: number,
  payloadOffset: number, unsynchronized: boolean): Promise<ArrayBuffer> {
  return taskpool.execute(
    readArtworkBytesTask, uri, byteOffset, byteLength, payloadOffset, unsynchronized
  ) as Promise<ArrayBuffer>;
}

export function flattenArtworkPixels(sourceBuffer: ArrayBuffer, width: number, height: number,
  premultiplied: boolean): Promise<ArrayBuffer> {
  return taskpool.execute(
    flattenArtworkPixelsTask, sourceBuffer, width, height, premultiplied
  ) as Promise<ArrayBuffer>;
}
