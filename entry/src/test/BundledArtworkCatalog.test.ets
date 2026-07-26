import { describe, expect, it } from '@ohos/hypium';
import { BundledArtworkCatalog } from '../main/ets/library/artwork/BundledArtworkCatalog';

export default function bundledArtworkCatalogTest() {
  describe('Bundled artwork catalog', () => {
    it('recognizes only bundled artwork paths', 0, () => {
      expect(BundledArtworkCatalog.isPath(BundledArtworkCatalog.DEMO_CITY_SMALL)).assertTrue();
      expect(BundledArtworkCatalog.isPath('file:///data/artwork.webp')).assertFalse();
    });

    it('promotes a bundled artwork path to the full morph variant', 0, () => {
      expect(BundledArtworkCatalog.fullPath(BundledArtworkCatalog.DEMO_COAST_LARGE))
        .assertEqual(BundledArtworkCatalog.DEMO_COAST_FULL);
      expect(BundledArtworkCatalog.fullPath('file:///data/artwork.webp'))
        .assertEqual('file:///data/artwork.webp');
    });
  });
}
