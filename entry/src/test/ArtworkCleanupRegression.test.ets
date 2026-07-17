import { describe, it, expect } from '@ohos/hypium';
import { ArtworkCleanupPolicy } from '../main/ets/library/artwork/ArtworkCleanupPolicy';

export default function artworkCleanupRegressionTest() {
  describe('Artwork cleanup policy', () => {
    it('normalizes recursive listing entries into cache-relative paths', 0, () => {
      expect(ArtworkCleanupPolicy.relativePath('/ab/cd/cover.jpg'))
        .assertEqual('artwork/ab/cd/cover.jpg');
      expect(ArtworkCleanupPolicy.relativePath('ab/cd/cover.jpg'))
        .assertEqual('artwork/ab/cd/cover.jpg');
    });

    it('protects referenced files and temporary files from orphan cleanup', 0, () => {
      const referenced = new Set<string>(['artwork/ab/cd/referenced.jpg']);
      expect(ArtworkCleanupPolicy.shouldDeleteOrphan('/ab/cd/referenced.jpg', true, referenced))
        .assertFalse();
      expect(ArtworkCleanupPolicy.shouldDeleteOrphan('/ab/cd/pending.tmp', true, referenced))
        .assertFalse();
      expect(ArtworkCleanupPolicy.shouldDeleteOrphan('/ab/cd/orphan.jpg', true, referenced))
        .assertTrue();
      expect(ArtworkCleanupPolicy.shouldDeleteOrphan('/ab/cd/folder', false, referenced))
        .assertFalse();
    });

    it('selects only temporary files for temporary cleanup', 0, () => {
      expect(ArtworkCleanupPolicy.shouldDeleteTemporary('/ab/cd/pending.tmp', true))
        .assertTrue();
      expect(ArtworkCleanupPolicy.shouldDeleteTemporary('/ab/cd/cover.jpg', true))
        .assertFalse();
      expect(ArtworkCleanupPolicy.shouldDeleteTemporary('/ab/cd/folder.tmp', false))
        .assertFalse();
    });

    it('bounds each deletion batch without skipping the tail', 0, () => {
      expect(ArtworkCleanupPolicy.batchEnd(0, 41)).assertEqual(16);
      expect(ArtworkCleanupPolicy.batchEnd(16, 41)).assertEqual(32);
      expect(ArtworkCleanupPolicy.batchEnd(32, 41)).assertEqual(41);
      expect(ArtworkCleanupPolicy.batchEnd(41, 41)).assertEqual(41);
    });
  });
}
