import { describe, it, expect } from '@ohos/hypium';
import { ArtworkLayout } from '../main/ets/components/artwork/ArtworkLayout';
import { ResourceLeaseRegistry } from '../main/ets/playback/artwork/ResourceLeaseRegistry';
import { RequestEpoch } from '../main/ets/playback/support/RequestEpoch';
import { DuplicatePolicy } from '../main/ets/library/importer/DuplicatePolicy';

class FakeResource {
  released: number = 0;
}

export default function riskRegressionTest() {
  describe('Risk regressions', () => {
    it('contains landscape and portrait artwork without changing the slot', 0, () => {
      const landscape = ArtworkLayout.containedSize(768, 432, 286, 286);
      const portrait = ArtworkLayout.containedSize(540, 768, 286, 286);
      expect(landscape.width).assertEqual(286);
      expect(Math.round(landscape.height)).assertEqual(161);
      expect(Math.round(portrait.width)).assertEqual(201);
      expect(portrait.height).assertEqual(286);
    });

    it('does not release an artwork while a transition lease is active', 0, () => {
      const registry = new ResourceLeaseRegistry<FakeResource>((resource: FakeResource) => {
        resource.released += 1;
      });
      const resource = new FakeResource();
      registry.acquire(resource);
      registry.requestRelease(resource);
      expect(resource.released).assertEqual(0);
      registry.release(resource);
      expect(resource.released).assertEqual(1);
    });

    it('invalidates stale playback requests immediately', 0, () => {
      const epoch = new RequestEpoch();
      const first = epoch.begin();
      epoch.invalidate();
      expect(epoch.isCurrent(first)).assertFalse();
      const second = epoch.begin();
      expect(epoch.isCurrent(second)).assertTrue();
    });

    it('never treats a quick fingerprint as final duplicate proof', 0, () => {
      expect(DuplicatePolicy.isConfirmedDuplicate('quick', 'quick', 'full-a', 'full-b')).assertFalse();
      expect(DuplicatePolicy.isConfirmedDuplicate('quick', 'quick', 'full-a', 'full-a')).assertTrue();
      expect(DuplicatePolicy.isConfirmedDuplicate('quick-a', 'quick-b', 'full-a', 'full-a')).assertTrue();
    });
  });
}
