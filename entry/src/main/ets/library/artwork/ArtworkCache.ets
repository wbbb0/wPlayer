import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { image } from '@kit.ImageKit';
import { SuppressWarnings, SuppressWarningsType } from '@ohos.annotation';
import { encodeArtworkWebP } from '../metadata/MediaFileTasks';
import { ImportPerformanceTrace } from '../importer/ImportPerformanceTrace';
import { ArtworkEncodingPolicy } from './ArtworkEncodingPolicy';
import { ArtworkCleanupPolicy } from './ArtworkCleanupPolicy';
import { ArtworkPalette, ArtworkPaletteExtractor } from './ArtworkPaletteExtractor';
import { extractArtworkPaletteAsync } from './ArtworkPaletteTasks';

const ARTWORK_DIRECTORY = 'artwork';
const TEMP_FILE_SUFFIX = '.tmp';
const MAX_SOURCE_BYTES = 32 * 1024 * 1024;
const MAX_SOURCE_EDGE = 32768;
const MAX_SOURCE_PIXELS = 100 * 1024 * 1024;

let temporaryFileSequence = 0;

export interface ArtworkCacheVariantResult {
  hash: string;
  relativePath: string;
  format: string;
  width: number;
  height: number;
  byteSize: number;
}

export interface ArtworkCacheResult {
  sourceHash: string;
  encodingVersion: number;
  small: ArtworkCacheVariantResult;
  large: ArtworkCacheVariantResult;
  palette: ArtworkPalette;
}

export class ArtworkCache {
  private readonly context: Context;
  private maintenanceTail: Promise<void> = Promise.resolve();

  constructor(context: Context) {
    this.context = context;
  }

  async cache(sourceBytes: Uint8Array, knownSourceHash?: string, traceFileId: number = 0,
    shouldContinue?: () => boolean): Promise<ArtworkCacheResult> {
    if (sourceBytes.byteLength === 0) {
      throw new Error('Artwork source is empty');
    }
    if (sourceBytes.byteLength > MAX_SOURCE_BYTES) {
      throw new Error(`Artwork source is too large: ${sourceBytes.byteLength}`);
    }

    const sourceHash = knownSourceHash ?? await ArtworkCache.sha256(sourceBytes);
    ArtworkCache.ensureContinues(shouldContinue);
    const sourceBuffer = ArtworkCache.toExactArrayBuffer(sourceBytes);
    const imageSource = image.createImageSource(sourceBuffer);
    try {
      const imageInfoStartedAt = Date.now();
      const imageInfo = await imageSource.getImageInfo();
      ArtworkCache.ensureContinues(shouldContinue);
      ImportPerformanceTrace.mark('artwork_info', imageInfoStartedAt, traceFileId,
        `source_bytes=${sourceBytes.byteLength} width=${imageInfo.size.width} height=${imageInfo.size.height}`);
      ArtworkCache.validateSourceDimensions(imageInfo.size.width, imageInfo.size.height);
      const large = await this.encodeVariant(
        sourceBuffer, sourceHash, imageInfo.size, ArtworkEncodingPolicy.LARGE_MAX_EDGE,
        'large', traceFileId
      );
      ArtworkCache.ensureContinues(shouldContinue);
      const small = await this.encodeVariant(
        sourceBuffer, sourceHash, imageInfo.size, ArtworkEncodingPolicy.SMALL_MAX_EDGE,
        'small', traceFileId
      );
      ArtworkCache.ensureContinues(shouldContinue);
      const paletteSource = image.createImageSource(ArtworkCache.copyArrayBuffer(sourceBuffer));
      let palettePixels: ArrayBuffer;
      try {
        palettePixels = await ArtworkPaletteExtractor.readPixelBuffer(paletteSource, imageInfo.size);
      } finally {
        await paletteSource.release();
      }
      ArtworkCache.ensureContinues(shouldContinue);
      const palette = await extractArtworkPaletteAsync(palettePixels);
      return {
        sourceHash: sourceHash,
        encodingVersion: ArtworkEncodingPolicy.VERSION,
        small: small,
        large: large,
        palette: palette
      };
    } finally {
      await imageSource.release();
    }
  }

  static hashSource(sourceBytes: Uint8Array): Promise<string> {
    if (sourceBytes.byteLength === 0) {
      throw new Error('Artwork source is empty');
    }
    return ArtworkCache.sha256(sourceBytes);
  }

  async extractPalette(relativePath: string): Promise<ArtworkPalette> {
    const imageSource = image.createImageSource(this.resolvePath(relativePath));
    try {
      const imageInfo = await imageSource.getImageInfo();
      ArtworkCache.validateSourceDimensions(imageInfo.size.width, imageInfo.size.height);
      const pixels = await ArtworkPaletteExtractor.readPixelBuffer(imageSource, imageInfo.size);
      return extractArtworkPaletteAsync(pixels);
    } finally {
      await imageSource.release();
    }
  }

  resolvePath(relativePath: string): string {
    return ArtworkCache.resolveContextPath(this.context, relativePath);
  }

  static resolveContextPath(context: Context, relativePath: string): string {
    const normalizedPath = ArtworkCache.validateRelativePath(relativePath);
    return `${context.filesDir}/${normalizedPath}`;
  }

  delete(relativePath: string): void {
    this.deleteAsync(relativePath).catch((error: Object): void => {
      console.warn(`Artwork cache delete failed: ${ArtworkCache.errorMessage(error)}`);
    });
  }

  async deleteAsync(relativePath: string): Promise<void> {
    await ArtworkCache.deleteIfPresentAsync(this.resolvePath(relativePath));
  }

  async existsAsync(relativePath: string): Promise<boolean> {
    if (relativePath.length === 0) {
      return false;
    }
    try {
      return await fs.access(this.resolvePath(relativePath));
    } catch (_) {
      return false;
    }
  }

  cleanupOrphans(referencedPaths: Array<string>, shouldContinue?: () => boolean): Promise<number> {
    const referenced = new Set<string>(referencedPaths);
    return this.enqueueMaintenance(async (): Promise<number> => {
      return this.cleanupEntries((entry: string, isFile: boolean): boolean =>
        ArtworkCleanupPolicy.shouldDeleteOrphan(entry, isFile, referenced), shouldContinue);
    });
  }

  clearAll(): void {
    this.enqueueMaintenance(async (): Promise<number> => {
      return this.cleanupEntries((_entry: string, isFile: boolean): boolean => isFile);
    }).catch((error: Object) => {
      console.warn(`Artwork cache clear failed: ${ArtworkCache.errorMessage(error)}`);
    });
  }

  cleanupTempFiles(shouldContinue?: () => boolean): Promise<number> {
    return this.enqueueMaintenance(async (): Promise<number> => {
      return this.cleanupEntries((entry: string, isFile: boolean): boolean =>
        ArtworkCleanupPolicy.shouldDeleteTemporary(entry, isFile), shouldContinue);
    });
  }

  cleanupEmptyDirectories(shouldContinue?: () => boolean): Promise<number> {
    return this.enqueueMaintenance(async (): Promise<number> => {
      return this.cleanupEmptyDirectoriesNow(shouldContinue);
    });
  }

  private async cleanupEntries(shouldDelete: (entry: string, isFile: boolean) => boolean,
    shouldContinue?: () => boolean): Promise<number> {
    try {
      const artworkRoot = ArtworkCache.resolveContextPath(this.context, ARTWORK_DIRECTORY);
      if (!await fs.access(artworkRoot)) {
        return 0;
      }
      let deletedCount = 0;
      const entries = await fs.listFile(artworkRoot, { recursion: true });
      for (let start = 0; start < entries.length;
        start = ArtworkCleanupPolicy.batchEnd(start, entries.length)) {
        if (shouldContinue !== undefined && !shouldContinue()) {
          break;
        }
        const end = ArtworkCleanupPolicy.batchEnd(start, entries.length);
        const batch = entries.slice(start, end);
        const results = await Promise.all(batch.map(async (entry: string): Promise<boolean> => {
          try {
            if (shouldContinue !== undefined && !shouldContinue()) {
              return false;
            }
            const relativeEntry = ArtworkCleanupPolicy.normalizedEntry(entry);
            if (relativeEntry.length === 0) {
              return false;
            }
            const path = `${artworkRoot}/${relativeEntry}`;
            const isFile = await ArtworkCache.isFile(path);
            if (!shouldDelete(entry, isFile) || (shouldContinue !== undefined && !shouldContinue())) {
              return false;
            }
            return ArtworkCache.deleteIfPresentAsync(path);
          } catch (error) {
            console.warn(`Artwork cleanup skipped a file: ${ArtworkCache.errorMessage(error)}`);
            return false;
          }
        }));
        results.forEach((deleted: boolean) => {
          if (deleted) {
            deletedCount += 1;
          }
        });
      }
      return deletedCount;
    } catch (error) {
      throw new Error(`Unable to enumerate artwork cache: ${ArtworkCache.errorMessage(error)}`);
    }
  }

  private enqueueMaintenance(operation: () => Promise<number>): Promise<number> {
    const result = this.maintenanceTail.then(operation);
    this.maintenanceTail = result.then((): void => {}, (error: Object): void => {
      console.warn(`Artwork maintenance failed: ${ArtworkCache.errorMessage(error)}`);
    });
    return result;
  }

  private async cleanupEmptyDirectoriesNow(shouldContinue?: () => boolean): Promise<number> {
    const artworkRoot = ArtworkCache.resolveContextPath(this.context, ARTWORK_DIRECTORY);
    if (!await ArtworkCache.pathExists(artworkRoot)) {
      return 0;
    }
    const directories: Array<string> = [];
    const pending: Array<string> = [artworkRoot];
    while (pending.length > 0) {
      if (shouldContinue !== undefined && !shouldContinue()) {
        return 0;
      }
      const directory = pending.pop();
      if (directory === undefined) {
        break;
      }
      const entries = await ArtworkCache.listDirectory(directory);
      for (let index = 0; index < entries.length; index += 1) {
        const entry = ArtworkCleanupPolicy.normalizedEntry(entries[index]);
        if (entry.length === 0 || entry.includes('/')) {
          continue;
        }
        const path = `${directory}/${entry}`;
        if (await ArtworkCache.isDirectory(path)) {
          directories.push(path);
          pending.push(path);
        }
      }
    }
    directories.sort((left: string, right: string): number => right.length - left.length);
    let deletedCount = 0;
    for (let index = 0; index < directories.length; index += 1) {
      if (shouldContinue !== undefined && !shouldContinue()) {
        break;
      }
      try {
        // HarmonyOS rmdir removes a directory tree even when it is not empty.
        // Only invoke it after a fresh emptiness check so referenced artwork is
        // never treated as collateral directory contents.
        const remainingEntries = await ArtworkCache.listDirectory(directories[index]);
        if (remainingEntries.length > 0) {
          continue;
        }
        await fs.rmdir(directories[index]);
        deletedCount += 1;
      } catch (error) {
        if (!await ArtworkCache.pathExists(directories[index])) {
          continue;
        }
        const remainingEntries = await ArtworkCache.listDirectory(directories[index]);
        if (remainingEntries.length === 0) {
          throw new Error(`Unable to remove empty artwork directory: ${ArtworkCache.errorMessage(error)}`);
        }
      }
    }
    return deletedCount;
  }

  private async encodeVariant(
    sourceBuffer: ArrayBuffer,
    sourceHash: string,
    sourceSize: image.Size,
    maxEdge: number,
    variantName: string,
    traceFileId: number
  ): Promise<ArtworkCacheVariantResult> {
    const variantStartedAt = Date.now();
    const targetSize = ArtworkEncodingPolicy.targetSize(sourceSize.width, sourceSize.height, maxEdge);
    const imageSource = image.createImageSource(ArtworkCache.copyArrayBuffer(sourceBuffer));
    let pixelMap: image.PixelMap | undefined;
    let temporaryPath = '';
    try {
      pixelMap = await imageSource.createPixelMap({
        desiredSize: targetSize,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const actualInfo = await pixelMap.getImageInfo();
      if (actualInfo.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
        throw new Error(`Unexpected artwork pixel format: ${actualInfo.pixelFormat}`);
      }
      const stride = actualInfo.size.width * 4;
      const pixels = new ArrayBuffer(stride * actualInfo.size.height);
      await pixelMap.readPixels({
        pixels: pixels,
        offset: 0,
        stride: stride,
        region: { x: 0, y: 0, size: actualInfo.size }
      });
      const encoded = await encodeArtworkWebP(
        pixels,
        actualInfo.size.width,
        actualInfo.size.height,
        actualInfo.alphaType === image.AlphaType.PREMUL,
        ArtworkEncodingPolicy.QUALITY,
        ArtworkEncodingPolicy.METHOD,
        ArtworkEncodingPolicy.ALPHA_QUALITY
      );
      const artworkRoot = ArtworkCache.resolveContextPath(this.context, ARTWORK_DIRECTORY);
      await ArtworkCache.ensureDirectoryAsync(artworkRoot);
      temporaryPath = `${artworkRoot}/.${sourceHash}.${variantName}.` +
        `${ArtworkCache.nextTemporaryId()}${TEMP_FILE_SUFFIX}`;
      const temporaryFile = await fs.open(temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        await ArtworkCache.writeAll(temporaryFile.fd, encoded);
      } finally {
        try {
          await fs.close(temporaryFile);
        } catch (error) {
          console.warn(`Unable to close temporary artwork file: ${ArtworkCache.errorMessage(error)}`);
        }
      }

      const contentHash = await hash.hash(temporaryPath, 'sha256');
      const relativePath = ArtworkCache.variantRelativePath(
        contentHash, ArtworkEncodingPolicy.EXTENSION
      );
      const finalPath = ArtworkCache.resolveContextPath(this.context, relativePath);
      await ArtworkCache.ensureDirectoryAsync(ArtworkCache.parentDirectory(finalPath));
      if (await fs.access(finalPath)) {
        await ArtworkCache.deleteIfPresentAsync(temporaryPath);
        temporaryPath = '';
      } else {
        try {
          await fs.rename(temporaryPath, finalPath);
          temporaryPath = '';
        } catch (_) {
          if (!await fs.access(finalPath)) {
            throw new Error(`Failed to commit ${variantName} artwork cache: ${contentHash}`);
          }
          await ArtworkCache.deleteIfPresentAsync(temporaryPath);
          temporaryPath = '';
        }
      }
      const result: ArtworkCacheVariantResult = {
        hash: contentHash,
        relativePath: relativePath,
        format: ArtworkEncodingPolicy.MIME_TYPE,
        width: actualInfo.size.width,
        height: actualInfo.size.height,
        byteSize: (await fs.stat(finalPath)).size
      };
      ImportPerformanceTrace.mark(`artwork_${variantName}`, variantStartedAt, traceFileId,
        `width=${result.width} height=${result.height} bytes=${result.byteSize}`);
      return result;
    } catch (error) {
      throw new Error(`Unable to encode ${variantName} artwork: ${ArtworkCache.errorMessage(error)}`);
    } finally {
      try {
        if (temporaryPath.length > 0) {
          await ArtworkCache.deleteIfPresentAsync(temporaryPath);
        }
      } finally {
        if (pixelMap !== undefined) {
          await pixelMap.release();
        }
      }
      await imageSource.release();
    }
  }

  @SuppressWarnings({ rules: [SuppressWarningsType.SYSCAP] })
  private static async sha256(bytes: Uint8Array): Promise<string> {
    try {
      const digest = cryptoFramework.createMd('SHA256');
      await digest.update({ data: bytes });
      const result = await digest.digest();
      let hexadecimal = '';
      result.data.forEach((value: number) => {
        hexadecimal += value.toString(16).padStart(2, '0');
      });
      return hexadecimal;
    } catch (error) {
      throw new Error(`Unable to hash artwork: ${ArtworkCache.errorMessage(error)}`);
    }
  }

  private static toExactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
      return bytes.buffer;
    }
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  }

  private static copyArrayBuffer(buffer: ArrayBuffer): ArrayBuffer {
    return buffer.slice(0);
  }

  private static validateSourceDimensions(width: number, height: number): void {
    if (width <= 0 || height <= 0 || width > MAX_SOURCE_EDGE || height > MAX_SOURCE_EDGE ||
      width > Math.floor(MAX_SOURCE_PIXELS / height)) {
      throw new Error(`Artwork dimensions exceed the import budget: ${width}x${height}`);
    }
  }

  private static variantRelativePath(contentHash: string, extension: string): string {
    return `${ARTWORK_DIRECTORY}/${contentHash.substring(0, 2)}/` +
      `${contentHash.substring(2, 4)}/${contentHash}.${extension}`;
  }

  private static validateRelativePath(relativePath: string): string {
    const normalizedPath = relativePath.replace(/\\/g, '/');
    const segments = normalizedPath.split('/');
    if (normalizedPath.length === 0 || normalizedPath.startsWith('/') ||
      segments.some((segment: string) => segment.length === 0 || segment === '.' || segment === '..') ||
      segments[0] !== ARTWORK_DIRECTORY) {
      throw new Error(`Invalid artwork relative path: ${relativePath}`);
    }
    return normalizedPath;
  }

  private static async ensureDirectoryAsync(path: string): Promise<void> {
    try {
      if (!await fs.access(path)) {
        await fs.mkdir(path, true);
      }
    } catch (error) {
      try {
        if (await fs.access(path)) {
          return;
        }
      } catch (_) {
      }
      throw new Error(`Unable to create artwork directory ${path}: ${ArtworkCache.errorMessage(error)}`);
    }
  }

  private static parentDirectory(path: string): string {
    const separator = path.lastIndexOf('/');
    if (separator <= 0) {
      throw new Error(`Invalid artwork path: ${path}`);
    }
    return path.substring(0, separator);
  }

  private static async deleteIfPresentAsync(path: string): Promise<boolean> {
    try {
      await fs.unlink(path);
      return true;
    } catch (error) {
      try {
        if (!await fs.access(path)) {
          return false;
        }
      } catch (accessError) {
        throw new Error(`Unable to verify artwork deletion ${path}: ${ArtworkCache.errorMessage(accessError)}`);
      }
      throw new Error(`Failed to delete artwork file: ${ArtworkCache.errorMessage(error)}`);
    }
  }

  private static async isFile(path: string): Promise<boolean> {
    try {
      const stat = await fs.stat(path);
      return stat.isFile();
    } catch (_) {
      return false;
    }
  }

  private static async isDirectory(path: string): Promise<boolean> {
    try {
      const stat = await fs.stat(path);
      return stat.isDirectory();
    } catch (_) {
      return false;
    }
  }

  private static async pathExists(path: string): Promise<boolean> {
    try {
      return await fs.access(path);
    } catch (_) {
      return false;
    }
  }

  private static async listDirectory(path: string): Promise<Array<string>> {
    try {
      return await fs.listFile(path);
    } catch (error) {
      throw new Error(`Unable to list artwork directory: ${ArtworkCache.errorMessage(error)}`);
    }
  }

  private static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }

  private static nextTemporaryId(): string {
    temporaryFileSequence++;
    return `${Date.now()}.${temporaryFileSequence}`;
  }

  private static async writeAll(fd: number, buffer: ArrayBuffer): Promise<void> {
    try {
      let offset = 0;
      while (offset < buffer.byteLength) {
        // WriteOptions.offset moves the file position, not the source-buffer start.
        const remaining = offset === 0 ? buffer : buffer.slice(offset);
        const written = await fs.write(fd, remaining);
        if (written <= 0) {
          throw new Error(`Unable to write artwork cache at offset ${offset}`);
        }
        offset += written;
      }
    } catch (error) {
      throw new Error(`Unable to write artwork cache: ${ArtworkCache.errorMessage(error)}`);
    }
  }

  private static ensureContinues(shouldContinue?: () => boolean): void {
    if (shouldContinue !== undefined && !shouldContinue()) {
      throw new Error('Artwork operation cancelled');
    }
  }
}
