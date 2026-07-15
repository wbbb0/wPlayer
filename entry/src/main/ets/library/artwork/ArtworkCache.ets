import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { image } from '@kit.ImageKit';

const ARTWORK_DIRECTORY = 'artwork';
const SMALL_MAX_EDGE = 256;
const LARGE_MAX_EDGE = 768;
const HEIF_QUALITY = 92;
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
  small: ArtworkCacheVariantResult;
  large: ArtworkCacheVariantResult;
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
    const imagePacker = image.createImagePacker();
    try {
      const imageInfo = await imageSource.getImageInfo();
      ArtworkCache.validateSourceDimensions(imageInfo.size.width, imageInfo.size.height);
      if (!ArtworkCache.supportsFormat(imagePacker.supportedFormats, 'heif')) {
        throw new Error('HEIF encoding is not supported on this device');
      }
      const small = await this.encodeVariant(
        imageSource, imagePacker, sourceHash, imageInfo.size, SMALL_MAX_EDGE,
        'image/heif', HEIF_QUALITY, 'heif', 'small'
      );
      const large = await this.encodeVariant(
        imageSource, imagePacker, sourceHash, imageInfo.size, LARGE_MAX_EDGE,
        'image/heif', HEIF_QUALITY, 'heif', 'large'
      );
      return { sourceHash: sourceHash, small: small, large: large };
    } finally {
      try {
        await imagePacker.release();
      } finally {
        await imageSource.release();
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
    ArtworkCache.deleteIfPresent(this.resolvePath(relativePath));
  }

  clearAll(): number {
    const artworkRoot = ArtworkCache.resolvePath(this.context, ARTWORK_DIRECTORY);
    if (!fs.accessSync(artworkRoot)) {
      return 0;
    }
    let deletedCount = 0;
    const entries = fs.listFileSync(artworkRoot, { recursion: true });
    entries.forEach((entry: string) => {
      const relativeEntry = entry.startsWith('/') ? entry.substring(1) : entry;
      const path = `${artworkRoot}/${relativeEntry}`;
      if (fs.statSync(path).isFile()) {
        ArtworkCache.deleteIfPresent(path);
        deletedCount++;
      }
    });
    return deletedCount;
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

  private async encodeVariant(
    imageSource: image.ImageSource,
    imagePacker: image.ImagePacker,
    sourceHash: string,
    sourceSize: image.Size,
    maxEdge: number,
    format: string,
    quality: number,
    extension: string,
    variantName: string
  ): Promise<ArtworkCacheVariantResult> {
    const targetSize = ArtworkCache.calculateTargetSize(sourceSize.width, sourceSize.height, maxEdge);
    const pixelMap = await imageSource.createPixelMap({
      desiredSize: targetSize,
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
    });
    let opaquePixelMap: image.PixelMap | undefined;
    let temporaryPath = '';
    try {
      opaquePixelMap = await ArtworkCache.flattenOntoWhite(pixelMap);
      const actualInfo = await opaquePixelMap.getImageInfo();
      const artworkRoot = ArtworkCache.resolvePath(this.context, ARTWORK_DIRECTORY);
      ArtworkCache.ensureDirectory(artworkRoot);
      temporaryPath = `${artworkRoot}/.${sourceHash}.${variantName}.` +
        `${ArtworkCache.nextTemporaryId()}${TEMP_FILE_SUFFIX}`;
      const temporaryFile = fs.openSync(temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        await imagePacker.packToFile(opaquePixelMap, temporaryFile.fd, {
          format: format,
          quality: quality
        });
      } finally {
        fs.closeSync(temporaryFile);
      }

      const contentHash = await hash.hash(temporaryPath, 'sha256');
      const relativePath = ArtworkCache.variantRelativePath(contentHash, extension);
      const finalPath = ArtworkCache.resolvePath(this.context, relativePath);
      ArtworkCache.ensureDirectory(ArtworkCache.parentDirectory(finalPath));
      if (fs.accessSync(finalPath)) {
        ArtworkCache.deleteIfPresent(temporaryPath);
        temporaryPath = '';
      } else {
        try {
          fs.renameSync(temporaryPath, finalPath);
          temporaryPath = '';
        } catch (_) {
          if (!fs.accessSync(finalPath)) {
            throw new Error(`Failed to commit ${variantName} artwork cache: ${contentHash}`);
          }
          ArtworkCache.deleteIfPresent(temporaryPath);
          temporaryPath = '';
        }
      }
      return {
        hash: contentHash,
        relativePath: relativePath,
        format: format,
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
          if (opaquePixelMap !== undefined) {
            await opaquePixelMap.release();
          }
        } finally {
          await pixelMap.release();
        }
      }
    }
  }

  private static async flattenOntoWhite(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    const info = await pixelMap.getImageInfo();
    if (info.pixelFormat !== image.PixelMapFormat.RGBA_8888) {
      throw new Error(`Unexpected artwork pixel format: ${info.pixelFormat}`);
    }
    const packedStride = info.size.width * 4;
    const sourceBuffer = new ArrayBuffer(packedStride * info.size.height);
    await pixelMap.readPixels({
      pixels: sourceBuffer,
      offset: 0,
      stride: packedStride,
      region: { x: 0, y: 0, size: info.size }
    });
    const source = new Uint8Array(sourceBuffer);
    const opaque = new Uint8Array(info.size.width * info.size.height * 4);
    const premultiplied = info.alphaType === image.AlphaType.PREMUL;
    for (let y = 0; y < info.size.height; y++) {
      for (let x = 0; x < info.size.width; x++) {
        const sourceOffset = y * packedStride + x * 4;
        const targetOffset = (y * info.size.width + x) * 4;
        const alpha = source[sourceOffset + 3];
        const white = 255 - alpha;
        for (let channel = 0; channel < 3; channel++) {
          // readPixels(PositionArea) returns BGRA; write an RGBA buffer for ImagePacker.
          const sourceChannel = channel === 0 ? 2 : channel === 2 ? 0 : 1;
          const color = source[sourceOffset + sourceChannel];
          opaque[targetOffset + channel] = premultiplied ?
            Math.min(255, color + white) : Math.round((color * alpha) / 255 + white);
        }
        opaque[targetOffset + 3] = 255;
      }
    }
    return image.createPixelMap(opaque.buffer, {
      size: info.size,
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE,
      editable: false
    });
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

  private static calculateTargetSize(width: number, height: number, maxEdge: number): image.Size {
    if (width <= 0 || height <= 0) {
      throw new Error(`Invalid artwork dimensions: ${width}x${height}`);
    }
    const scale = Math.min(1, maxEdge / Math.max(width, height));
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

  private static supportsFormat(formats: Array<string>, expected: string): boolean {
    return formats.some((format: string) => {
      const normalized = format.toLowerCase().replace('image/', '');
      if (expected === 'heif') {
        return normalized === 'heif' || normalized === 'heic';
      }
      return normalized === expected;
    });
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
