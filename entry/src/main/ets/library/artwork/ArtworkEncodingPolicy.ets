import { image } from '@kit.ImageKit';

export class ArtworkEncodingPolicy {
  static readonly VERSION: number = 2;
  static readonly MIME_TYPE: string = 'image/webp';
  static readonly EXTENSION: string = 'webp';
  static readonly QUALITY: number = 84;
  static readonly METHOD: number = 4;
  static readonly ALPHA_QUALITY: number = 100;
  static readonly SMALL_MAX_EDGE: number = 256;
  static readonly LARGE_MAX_EDGE: number = 768;

  static isCurrent(version: number, smallFormat: string, largeFormat: string): boolean {
    return version === ArtworkEncodingPolicy.VERSION &&
      ArtworkEncodingPolicy.comparisonFormat(smallFormat) === ArtworkEncodingPolicy.MIME_TYPE &&
      ArtworkEncodingPolicy.comparisonFormat(largeFormat) === ArtworkEncodingPolicy.MIME_TYPE;
  }

  static targetSize(width: number, height: number, maxEdge: number): image.Size {
    if (width <= 0 || height <= 0) {
      return { width: 0, height: 0 };
    }
    const scale = Math.min(1, maxEdge / Math.max(width, height));
    return {
      width: Math.max(1, Math.round(width * scale)),
      height: Math.max(1, Math.round(height * scale))
    };
  }

  private static comparisonFormat(format: string): string {
    return format.toLowerCase();
  }
}
