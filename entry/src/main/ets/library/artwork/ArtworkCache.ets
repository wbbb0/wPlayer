import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { image } from '@kit.ImageKit';

const ARTWORK_DIRECTORY = 'artwork';
const THUMBNAIL_MAX_EDGE = 512;
const WEBP_QUALITY = 85;
const TEMP_FILE_SUFFIX = '.tmp';
const MAX_SOURCE_BYTES = 32 * 1024 * 1024;
const MAX_SOURCE_EDGE = 32768;
const MAX_SOURCE_PIXELS = 100 * 1024 * 1024;

let temporaryFileSequence = 0;

export interface ArtworkCacheResult {
  sourceHash: string;
  thumbnailHash: string;
  relativePath: string;
  width: number;
  height: number;
  byteSize: number;
}

export class ArtworkCache {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  async cache(sourceBytes: Uint8Array, knownSourceHash?: string): Promise<ArtworkCacheResult> {
    if (sourceBytes.byteLength === 0) {
      throw new Error('Artwork source is empty');
    }
    if (sourceBytes.byteLength > MAX_SOURCE_BYTES) {
      throw new Error(`Artwork source is too large: ${sourceBytes.byteLength}`);
    }

    const sourceHash = knownSourceHash ?? await ArtworkCache.sha256(sourceBytes);
    const sourceBuffer = ArtworkCache.toExactArrayBuffer(sourceBytes);
    const imageSource = image.createImageSource(sourceBuffer);
    let pixelMap: image.PixelMap | undefined = undefined;
    let imagePacker: image.ImagePacker | undefined = undefined;
    let temporaryPath = '';

    try {
      const imageInfo = await imageSource.getImageInfo();
      ArtworkCache.validateSourceDimensions(imageInfo.size.width, imageInfo.size.height);
      const targetSize = ArtworkCache.calculateTargetSize(imageInfo.size.width, imageInfo.size.height);
      pixelMap = await imageSource.createPixelMap({
        desiredSize: targetSize
      });

      const actualInfo = await pixelMap.getImageInfo();
      imagePacker = image.createImagePacker();
      if (!ArtworkCache.supportsWebp(imagePacker.supportedFormats)) {
        throw new Error('WebP encoding is not supported on this device');
      }

      const artworkRoot = ArtworkCache.resolvePath(this.context, ARTWORK_DIRECTORY);
      ArtworkCache.ensureDirectory(artworkRoot);
      temporaryPath = `${artworkRoot}/.${sourceHash}.${ArtworkCache.nextTemporaryId()}${TEMP_FILE_SUFFIX}`;
      const temporaryFile = fs.openSync(temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        await imagePacker.packToFile(pixelMap, temporaryFile.fd, {
          format: 'image/webp',
          quality: WEBP_QUALITY
        });
      } finally {
        fs.closeSync(temporaryFile);
      }

      const thumbnailHash = await hash.hash(temporaryPath, 'sha256');
      const relativePath = ArtworkCache.thumbnailRelativePath(thumbnailHash);
      const finalPath = ArtworkCache.resolvePath(this.context, relativePath);
      const finalDirectory = ArtworkCache.parentDirectory(finalPath);
      ArtworkCache.ensureDirectory(finalDirectory);

      if (fs.accessSync(finalPath)) {
        ArtworkCache.deleteIfPresent(temporaryPath);
        temporaryPath = '';
      } else {
        try {
          fs.renameSync(temporaryPath, finalPath);
          temporaryPath = '';
        } catch (_) {
          // Another import may have committed the same content-addressed file first.
          if (!fs.accessSync(finalPath)) {
            throw new Error(`Failed to commit artwork thumbnail: ${thumbnailHash}`);
          }
          ArtworkCache.deleteIfPresent(temporaryPath);
          temporaryPath = '';
        }
      }

      return {
        sourceHash: sourceHash,
        thumbnailHash: thumbnailHash,
        relativePath: relativePath,
        width: actualInfo.size.width,
        height: actualInfo.size.height,
        byteSize: fs.statSync(finalPath).size
      };
    } finally {
      try {
        if (temporaryPath.length > 0) {
          ArtworkCache.deleteIfPresent(temporaryPath);
        }
      } finally {
        try {
          if (imagePacker !== undefined) {
            await imagePacker.release();
          }
        } finally {
          try {
            if (pixelMap !== undefined) {
              await pixelMap.release();
            }
          } finally {
            await imageSource.release();
          }
        }
      }
    }
  }

  static hashSource(sourceBytes: Uint8Array): Promise<string> {
    if (sourceBytes.byteLength === 0) {
      throw new Error('Artwork source is empty');
    }
    return ArtworkCache.sha256(sourceBytes);
  }

  resolvePath(relativePath: string): string {
    return ArtworkCache.resolvePath(this.context, relativePath);
  }

  static resolvePath(context: Context, relativePath: string): string {
    const normalizedPath = ArtworkCache.validateRelativePath(relativePath);
    return `${context.filesDir}/${normalizedPath}`;
  }

  delete(relativePath: string): void {
    const path = this.resolvePath(relativePath);
    ArtworkCache.deleteIfPresent(path);
  }

  cleanupTempFiles(): number {
    const artworkRoot = ArtworkCache.resolvePath(this.context, ARTWORK_DIRECTORY);
    if (!fs.accessSync(artworkRoot)) {
      return 0;
    }

    let deletedCount = 0;
    const entries = fs.listFileSync(artworkRoot, { recursion: true });
    entries.forEach((entry: string) => {
      if (!entry.endsWith(TEMP_FILE_SUFFIX)) {
        return;
      }
      const relativeEntry = entry.startsWith('/') ? entry.substring(1) : entry;
      const path = `${artworkRoot}/${relativeEntry}`;
      if (fs.statSync(path).isFile()) {
        ArtworkCache.deleteIfPresent(path);
        deletedCount++;
      }
    });
    return deletedCount;
  }

  private static async sha256(bytes: Uint8Array): Promise<string> {
    const digest = cryptoFramework.createMd('SHA256');
    await digest.update({ data: bytes });
    const result = await digest.digest();
    let hexadecimal = '';
    result.data.forEach((value: number) => {
      hexadecimal += value.toString(16).padStart(2, '0');
    });
    return hexadecimal;
  }

  private static toExactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
      return bytes.buffer;
    }
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  }

  private static calculateTargetSize(width: number, height: number): image.Size {
    if (width <= 0 || height <= 0) {
      throw new Error(`Invalid artwork dimensions: ${width}x${height}`);
    }
    const scale = Math.min(1, THUMBNAIL_MAX_EDGE / Math.max(width, height));
    return {
      width: Math.max(1, Math.round(width * scale)),
      height: Math.max(1, Math.round(height * scale))
    };
  }

  private static validateSourceDimensions(width: number, height: number): void {
    if (width <= 0 || height <= 0 || width > MAX_SOURCE_EDGE || height > MAX_SOURCE_EDGE ||
      width > Math.floor(MAX_SOURCE_PIXELS / height)) {
      throw new Error(`Artwork dimensions exceed the import budget: ${width}x${height}`);
    }
  }

  private static supportsWebp(formats: Array<string>): boolean {
    return formats.some((format: string) => {
      const normalizedFormat = format.toLowerCase();
      return normalizedFormat === 'image/webp' || normalizedFormat === 'webp';
    });
  }

  private static thumbnailRelativePath(thumbnailHash: string): string {
    return `${ARTWORK_DIRECTORY}/${thumbnailHash.substring(0, 2)}/${thumbnailHash.substring(2, 4)}/${thumbnailHash}.webp`;
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

  private static ensureDirectory(path: string): void {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  }

  private static parentDirectory(path: string): string {
    const separator = path.lastIndexOf('/');
    if (separator <= 0) {
      throw new Error(`Invalid artwork path: ${path}`);
    }
    return path.substring(0, separator);
  }

  private static deleteIfPresent(path: string): void {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  }

  private static nextTemporaryId(): string {
    temporaryFileSequence++;
    return `${Date.now()}.${temporaryFileSequence}`;
  }
}
