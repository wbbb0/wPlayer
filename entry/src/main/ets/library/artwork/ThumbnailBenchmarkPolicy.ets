export enum ThumbnailBenchmarkMethod {
  SYSTEM_JPEG = 'system_jpeg',
  CPP_WEBP = 'cpp_webp'
}

export interface ThumbnailBenchmarkOptions {
  methods: Array<ThumbnailBenchmarkMethod>;
  maxEdge: number;
  sampleCount: number;
}

export class ThumbnailBenchmarkPolicy {
  static readonly DEFAULT_SAMPLE_COUNT: number = 50;
  static readonly MAX_SAMPLE_COUNT: number = 1000;
  static readonly RESOLUTIONS: Array<number> = [256, 512, 768, 1024];

  static normalizeSampleCount(value: number): number {
    if (!Number.isFinite(value)) {
      return ThumbnailBenchmarkPolicy.DEFAULT_SAMPLE_COUNT;
    }
    return Math.min(
      ThumbnailBenchmarkPolicy.MAX_SAMPLE_COUNT,
      Math.max(1, Math.floor(value))
    );
  }

  static isSupportedResolution(value: number): boolean {
    return ThumbnailBenchmarkPolicy.RESOLUTIONS.includes(value);
  }

  static sample<T>(items: Array<T>, requestedCount: number,
    random: () => number = Math.random): Array<T> {
    const shuffled = items.slice();
    for (let index = shuffled.length - 1; index > 0; index -= 1) {
      const randomValue = Math.min(0.999999999, Math.max(0, random()));
      const swapIndex = Math.floor(randomValue * (index + 1));
      const current = shuffled[index];
      shuffled[index] = shuffled[swapIndex];
      shuffled[swapIndex] = current;
    }
    return shuffled.slice(0, Math.min(
      shuffled.length,
      ThumbnailBenchmarkPolicy.normalizeSampleCount(requestedCount)
    ));
  }

  static average(totalMs: number, successCount: number): number {
    return successCount > 0 ? totalMs / successCount : 0;
  }
}
