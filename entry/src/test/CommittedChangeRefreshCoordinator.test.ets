import { describe, expect, it } from '@ohos/hypium';
import {
  CommittedChangeRefreshCoordinator
} from '../main/ets/library/importer/CommittedChangeRefreshCoordinator';

export default function committedChangeRefreshCoordinatorTest() {
  describe('Committed change refresh coordinator', () => {
    it('publishesTheFirstCommitThenCoalescesBatchesAndFlushesTheRemainder', 0, async () => {
      let refreshCount = 0;
      const coordinator = new CommittedChangeRefreshCoordinator(async (): Promise<void> => {
        refreshCount += 1;
      }, 4);
      coordinator.recordCommitted();
      await coordinator.flush();
      expect(refreshCount).assertEqual(1);
      coordinator.recordCommitted(3);
      await coordinator.flush();
      expect(refreshCount).assertEqual(2);
      coordinator.recordCommitted(4);
      await coordinator.flush();
      expect(refreshCount).assertEqual(3);
    });

    it('neverRunsProjectionRefreshesConcurrently', 0, async () => {
      let active = 0;
      let maximumActive = 0;
      const coordinator = new CommittedChangeRefreshCoordinator(async (): Promise<void> => {
        active += 1;
        maximumActive = Math.max(maximumActive, active);
        await Promise.resolve();
        active -= 1;
      }, 1);
      coordinator.recordCommitted();
      coordinator.recordCommitted();
      coordinator.recordCommitted();
      await coordinator.flush();
      expect(maximumActive).assertEqual(1);
    });

    it('propagatesARefreshFailureWithoutStartingAnUnboundedRetryLoop', 0, async () => {
      let attempts = 0;
      const coordinator = new CommittedChangeRefreshCoordinator(async (): Promise<void> => {
        attempts += 1;
        throw new Error('refresh failed');
      }, 1);
      coordinator.recordCommitted();
      let rejected = false;
      try {
        await coordinator.flush();
      } catch (_) {
        rejected = true;
      }
      await Promise.resolve();
      expect(rejected).assertTrue();
      expect(attempts).assertEqual(1);
    });
  });
}
