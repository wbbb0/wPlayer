import { describe, expect, it } from '@ohos/hypium';
import { ArtworkSourceIdentityPolicy } from
  '../main/ets/library/artwork/ArtworkSourceIdentityPolicy';

export default function artworkSourceIdentityPolicyTest() {
  describe('Artwork source identity policy', () => {
    it('acceptsOnlyCanonicalCurrentAndLegacyIdentities', 0, () => {
      const current = ArtworkSourceIdentityPolicy.fromCurrentDigest('A'.repeat(32));
      expect(current).assertEqual(`xxh3-128:${'a'.repeat(32)}`);
      expect(ArtworkSourceIdentityPolicy.isCurrent(current)).assertTrue();
      expect(ArtworkSourceIdentityPolicy.isCurrent(`xxh3-128:${'g'.repeat(32)}`)).assertFalse();
      expect(ArtworkSourceIdentityPolicy.isLegacySha256('b'.repeat(64))).assertTrue();
      expect(ArtworkSourceIdentityPolicy.isLegacySha256('b'.repeat(63))).assertFalse();
    });

    it('versionsVariantCacheKeysIndependently', 0, () => {
      const identity = `xxh3-128:${'c'.repeat(32)}`;
      expect(ArtworkSourceIdentityPolicy.cacheKey(identity, 3, 'small'))
        .assertEqual(`${identity}:v3:small`);
      expect(ArtworkSourceIdentityPolicy.cacheKey(identity, 3, 'large'))
        .assertEqual(`${identity}:v3:large`);
      expect(ArtworkSourceIdentityPolicy.cacheKey(identity, 3, 'small') ===
        ArtworkSourceIdentityPolicy.cacheKey(identity, 4, 'small')).assertFalse();
    });
  });
}
