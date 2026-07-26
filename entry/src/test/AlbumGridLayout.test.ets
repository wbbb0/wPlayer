import { describe, expect, it } from '@ohos/hypium';
import { PageLayoutSpec } from '../main/ets/components/layout/PageLayoutSpec';

export default function albumGridLayoutTest() {
  describe('Album grid layout', () => {
    it('keeps at least two columns without changing wider-layout density', 0, () => {
      expect(PageLayoutSpec.albumColumnCount(320, PageLayoutSpec.HORIZONTAL_INSET)).assertEqual(2);
      expect(PageLayoutSpec.albumColumnCount(360, PageLayoutSpec.HORIZONTAL_INSET)).assertEqual(2);
      expect(PageLayoutSpec.albumColumnCount(400, PageLayoutSpec.HORIZONTAL_INSET)).assertEqual(2);
      expect(PageLayoutSpec.albumColumnCount(800, PageLayoutSpec.HORIZONTAL_INSET)).assertEqual(4);
    });

    it('builds an equal-width Grid template from the responsive policy', 0, () => {
      expect(PageLayoutSpec.albumColumnsTemplate(
        360,
        PageLayoutSpec.HORIZONTAL_INSET
      )).assertEqual('1fr 1fr');
      expect(PageLayoutSpec.albumColumnsTemplate(
        800,
        PageLayoutSpec.HORIZONTAL_INSET
      )).assertEqual('1fr 1fr 1fr 1fr');
    });

    it('derives an exact item width for non-scrolling grid rows', 0, () => {
      expect(PageLayoutSpec.albumItemWidth(
        360,
        PageLayoutSpec.HORIZONTAL_INSET
      )).assertEqual(152);
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
