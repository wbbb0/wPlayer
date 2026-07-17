import { describe, expect, it } from '@ohos/hypium';
import { PageLayoutSpec } from '../main/ets/components/layout/PageLayoutSpec';

export default function albumGridLayoutTest() {
  describe('Album grid layout', () => {
    it('derives responsive columns from the available width', 0, () => {
      expect(PageLayoutSpec.albumColumnCount(360, PageLayoutSpec.HORIZONTAL_INSET)).assertEqual(1);
      expect(PageLayoutSpec.albumColumnCount(400, PageLayoutSpec.HORIZONTAL_INSET)).assertEqual(2);
      expect(PageLayoutSpec.albumColumnCount(800, PageLayoutSpec.HORIZONTAL_INSET)).assertEqual(4);
    });

    it('derives an exact item width for non-scrolling grid rows', 0, () => {
      expect(PageLayoutSpec.albumItemWidth(
        400,
        PageLayoutSpec.HORIZONTAL_INSET
      )).assertEqual(172);
      expect(PageLayoutSpec.albumItemWidth(
        800,
        PageLayoutSpec.HORIZONTAL_INSET
      )).assertEqual(178);
    });
  });
}
