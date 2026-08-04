import { describe, expect, it } from '@ohos/hypium';
import {
  FullPlayerQueueRefreshPhase,
  FullPlayerQueueRefreshState
} from '../main/ets/components/player/FullPlayerQueueRefreshState';

export default function fullPlayerQueueRefreshStateTest() {
  describe('Full player queue refresh state', () => {
    it('keeps the queue unmounted until persistence completes', 0, () => {
      const state = new FullPlayerQueueRefreshState();
      const token = state.request();

      expect(token).assertEqual(1);
      expect(state.showsLoading()).assertTrue();
      expect(state.mountsQueue()).assertFalse();
      expect(state.markCommitting(token)).assertTrue();
      expect(state.showsLoading()).assertTrue();
      expect(state.markRebuilding(token)).assertTrue();
      expect(state.showsLoading()).assertFalse();
      expect(state.mountsQueue()).assertTrue();
      expect(state.queueVisible()).assertFalse();
      expect(state.markRevealing(token)).assertTrue();
      expect(state.complete(token)).assertTrue();
      expect(state.phase).assertEqual(FullPlayerQueueRefreshPhase.VISIBLE);
      expect(state.queueVisible()).assertTrue();
    });

    it('rejects rapid and stale transitions', 0, () => {
      const state = new FullPlayerQueueRefreshState();
      const token = state.request();

      expect(state.request()).assertEqual(-1);
      expect(state.markCommitting(token + 1)).assertFalse();
      expect(state.markRebuilding(token)).assertFalse();
      expect(state.phase).assertEqual(FullPlayerQueueRefreshPhase.UNMOUNTING);
      expect(state.complete(token)).assertTrue();
    });
  });
}
