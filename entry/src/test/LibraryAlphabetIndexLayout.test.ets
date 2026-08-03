import { describe, expect, it } from '@ohos/hypium';
import { LibraryAlphabetIndex } from '../main/ets/components/library/LibraryAlphabetIndex';

export default function libraryAlphabetIndexLayoutTest() {
  describe('Library alphabet index layout', () => {
    it('reserves the index track and interaction gap only while visible', 0, () => {
      expect(LibraryAlphabetIndex.contentGutter(true)).assertEqual(14);
      expect(LibraryAlphabetIndex.contentGutter(false)).assertEqual(0);
    });
  });
}
