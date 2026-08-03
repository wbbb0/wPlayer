import { describe, expect, it } from '@ohos/hypium';
import { AlbumPreviewLayoutPolicy } from '../main/ets/components/library/AlbumPreviewGrid';
import { PageLayoutSpec } from '../main/ets/components/layout/PageLayoutSpec';

export default function albumPreviewLayoutTest() {
  describe('Album preview layout policy', () => {
    it('clamps compact and wide card widths', 0, () => {
      expect(AlbumPreviewLayoutPolicy.itemWidth(320))
        .assertEqual(AlbumPreviewLayoutPolicy.MIN_ITEM_WIDTH);
      expect(AlbumPreviewLayoutPolicy.itemWidth(1200))
        .assertEqual(AlbumPreviewLayoutPolicy.MAX_ITEM_WIDTH);
    });

    it('reserves exactly two card rows', 0, () => {
      const width = AlbumPreviewLayoutPolicy.itemWidth(600);
      expect(AlbumPreviewLayoutPolicy.viewportHeight(600))
        .assertEqual((width + AlbumPreviewLayoutPolicy.CARD_TEXT_HEIGHT) * 2 +
          PageLayoutSpec.ALBUM_ROW_GAP);
    });
  });
}
