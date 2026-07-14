import { fileIo as fs } from '@kit.CoreFileKit';

export class BinaryFileReader {
  readonly fd: number;
  readonly size: number;
  readonly name: string;
  readonly modifiedAt: number;
  private closed: boolean = false;

  constructor(uri: string) {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      this.fd = file.fd;
      this.size = stat.size;
      this.modifiedAt = stat.mtime;
      this.name = file.name;
    } catch (error) {
      fs.closeSync(file);
      const message = error instanceof Error ? error.message : `${error}`;
      throw new Error(`Unable to inspect media file: ${message}`);
    }
  }

  close(): void {
    if (!this.closed) {
      fs.closeSync(this.fd);
      this.closed = true;
    }
  }

  read(offset: number, length: number): Uint8Array {
    if (offset < 0 || length < 0 || offset + length > this.size) {
      throw new Error(`Invalid file range: ${offset}+${length}/${this.size}`);
    }
    const output = new Uint8Array(length);
    let totalRead = 0;
    while (totalRead < length) {
      const chunkBuffer = new ArrayBuffer(length - totalRead);
      const bytesRead = fs.readSync(this.fd, chunkBuffer, {
        offset: offset + totalRead,
        length: length - totalRead
      });
      if (bytesRead <= 0) {
        throw new Error(`Unexpected end of file at ${offset + totalRead}`);
      }
      output.set(new Uint8Array(chunkBuffer, 0, bytesRead), totalRead);
      totalRead += bytesRead;
    }
    return output;
  }

  static uint16BE(bytes: Uint8Array, offset: number): number {
    return (bytes[offset] << 8) | bytes[offset + 1];
  }

  static uint24BE(bytes: Uint8Array, offset: number): number {
    return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
  }

  static uint32BE(bytes: Uint8Array, offset: number): number {
    return bytes[offset] * 0x1000000 + bytes[offset + 1] * 0x10000 + bytes[offset + 2] * 0x100 + bytes[offset + 3];
  }

  static uint32LE(bytes: Uint8Array, offset: number): number {
    return bytes[offset] + bytes[offset + 1] * 0x100 + bytes[offset + 2] * 0x10000 + bytes[offset + 3] * 0x1000000;
  }

  static syncSafe32(bytes: Uint8Array, offset: number): number {
    return (bytes[offset] << 21) | (bytes[offset + 1] << 14) | (bytes[offset + 2] << 7) | bytes[offset + 3];
  }
}
