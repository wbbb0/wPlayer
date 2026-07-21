import { describe, expect, it } from '@ohos/hypium';
import { MiniPlayerClickSuppressor } from '../main/ets/components/player/PlayerMotion';

export default function miniPlayerGesturePolicyTest() {
  describe('Mini player gesture policy', () => {
    it('suppresses only the click immediately following a recognized pan', 0, () => {
      const suppressor = new MiniPlayerClickSuppressor();

      expect(suppressor.consumeClickSuppression()).assertFalse();
      suppressor.markPanRecognized();
      expect(suppressor.consumeClickSuppression()).assertTrue();
      expect(suppressor.consumeClickSuppression()).assertFalse();
    });
  });
}
