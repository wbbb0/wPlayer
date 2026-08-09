import { describe, it, expect } from '@ohos/hypium';
import { ThumbnailBenchmarkPolicy } from
  '../main/ets/library/artwork/ThumbnailBenchmarkPolicy';

export default function thumbnailBenchmarkPolicyTest() {
  describe('Thumbnail benchmark policy', () => {
    it('normalizes the requested sample count', 0, () => {
      expect(ThumbnailBenchmarkPolicy.normalizeSampleCount(Number.NaN)).assertEqual(50);
      expect(ThumbnailBenchmarkPolicy.normalizeSampleCount(0)).assertEqual(1);
      expect(ThumbnailBenchmarkPolicy.normalizeSampleCount(12.9)).assertEqual(12);
      expect(ThumbnailBenchmarkPolicy.normalizeSampleCount(5000)).assertEqual(1000);
    });

    it('samples without mutating the catalog and respects the requested bound', 0, () => {
      const catalog = [1, 2, 3, 4];
      const randomValues = [0, 0.5, 0.99];
      let randomIndex = 0;
      const sampled = ThumbnailBenchmarkPolicy.sample(catalog, 3, (): number => {
        const value = randomValues[randomIndex];
        randomIndex += 1;
        return value;
      });

      expect(catalog.join(',')).assertEqual('1,2,3,4');
      expect(sampled.length).assertEqual(3);
      expect(new Set<number>(sampled).size).assertEqual(3);
    });

    it('uses only supported thumbnail resolutions', 0, () => {
      expect(ThumbnailBenchmarkPolicy.isSupportedResolution(256)).assertTrue();
      expect(ThumbnailBenchmarkPolicy.isSupportedResolution(1024)).assertTrue();
      expect(ThumbnailBenchmarkPolicy.isSupportedResolution(300)).assertFalse();
    });

    it('averages successful samples only', 0, () => {
      expect(ThumbnailBenchmarkPolicy.average(30, 2)).assertEqual(15);
      expect(ThumbnailBenchmarkPolicy.average(30, 0)).assertEqual(0);
    });
  });
}
