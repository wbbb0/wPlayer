import { describe, expect, it } from '@ohos/hypium';
import { PageLayoutSpec } from '../main/ets/components/layout/PageLayoutSpec';
import { AlbumDetailColorPolicy } from '../main/ets/pages/library/AlbumDetailPage';

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

    it('lets wide album-detail artwork exceed a square while preserving its ratio', 0, () => {
      const compactWide = PageLayoutSpec.albumDetailArtworkSize(1600, 900, 400, false);
      const compactSquare = PageLayoutSpec.albumDetailArtworkSize(900, 900, 400, false);
      const compactPortrait = PageLayoutSpec.albumDetailArtworkSize(900, 1600, 400, false);
      const unfoldedWide = PageLayoutSpec.albumDetailArtworkSize(1600, 900, 720, true);

      expect(Math.round(compactWide.width)).assertEqual(391);
      expect(Math.round(compactWide.height)).assertEqual(220);
      expect(compactWide.width > compactWide.height).assertTrue();
      expect(Math.round(compactSquare.width)).assertEqual(220);
      expect(Math.round(compactSquare.height)).assertEqual(220);
      expect(Math.round(compactPortrait.width)).assertEqual(124);
      expect(Math.round(compactPortrait.height)).assertEqual(220);
      expect(Math.round(unfoldedWide.width)).assertEqual(327);
      expect(Math.round(unfoldedWide.height)).assertEqual(184);
    });

    it('nudges album backgrounds away from the foreground color', 0, () => {
      expect(AlbumDetailColorPolicy.background('#FFFFE000')).assertEqual('#FFFFEA54');
      expect(AlbumDetailColorPolicy.background('#FF117A8B')).assertEqual('#FF005A68');
      expect(AlbumDetailColorPolicy.background('#FFFFFFFF')).assertEqual('#FFFFFFFF');
      expect(AlbumDetailColorPolicy.background('#FF000000')).assertEqual('#FF000000');
    });
  });
}
