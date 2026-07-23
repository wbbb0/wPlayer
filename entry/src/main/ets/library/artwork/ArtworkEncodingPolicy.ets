import { image } from '@kit.ImageKit';

export class ArtworkEncodingPolicy {
  static readonly MIME_TYPE: string = 'image/jpeg';
  static readonly EXTENSION: string = 'jpg';
  static readonly QUALITY: number = 90;
  static readonly SMALL_MAX_EDGE: number = 256;
  static readonly LARGE_MAX_EDGE: number = 768;

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
}
