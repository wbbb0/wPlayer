import { describe, expect, it } from '@ohos/hypium';
import { LibraryCollectionQueryPolicy } from '../main/ets/library/data/LibraryCollectionQueryPolicy';

export default function libraryCollectionPolicyTest() {
  describe('Library collection policy', () => {
    it('keeps detail previews bounded below paging windows', 0, () => {
      expect(LibraryCollectionQueryPolicy.ARTIST_TRACK_PREVIEW_LIMIT).assertEqual(10);
      expect(LibraryCollectionQueryPolicy.ARTIST_ALBUM_PREVIEW_LIMIT).assertEqual(12);
      expect(LibraryCollectionQueryPolicy.RELATED_ALBUM_PREVIEW_LIMIT).assertEqual(12);
    });
  });
}
