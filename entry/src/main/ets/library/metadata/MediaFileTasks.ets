import { taskpool } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo as fs } from '@kit.CoreFileKit';

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

export function calculateFullFingerprint(uri: string): Promise<string> {
  return taskpool.execute(calculateFullFingerprintTask, uri) as Promise<string>;
}

export function readArtworkBytesAsync(uri: string, byteOffset: number, byteLength: number,
  payloadOffset: number, unsynchronized: boolean): Promise<ArrayBuffer> {
  return taskpool.execute(
    readArtworkBytesTask, uri, byteOffset, byteLength, payloadOffset, unsynchronized
  ) as Promise<ArrayBuffer>;
}
