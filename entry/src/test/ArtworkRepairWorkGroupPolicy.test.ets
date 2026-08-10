import { describe, expect, it } from '@ohos/hypium';
import {
  ArtworkRepairWorkGroupPolicy
} from '../main/ets/library/artwork/ArtworkRepairWorkGroupPolicy';
import { ArtworkWorkOutcome, ArtworkWorkResult } from '../main/ets/library/artwork/ArtworkWorkSession';
import { ArtworkState } from '../main/ets/library/model/LibraryModels';

function result(outcome: ArtworkWorkOutcome): ArtworkWorkResult {
  return { outcome: outcome, sourceHasArtwork: true, errorMessage: '' };
}

export default function artworkRepairWorkGroupPolicyTest() {
  describe('Artwork repair work grouping', () => {
    it('groupsOnlyReadyArtworkWithAnExactSourceIdentity', 0, () => {
      expect(ArtworkRepairWorkGroupPolicy.sharedSourceKey(
        ArtworkState.READY, 12, 'source-hash'
      )).assertEqual('12:source-hash');
      expect(ArtworkRepairWorkGroupPolicy.sharedSourceKey(
        ArtworkState.FAILED, 12, 'source-hash'
      )).assertEqual('');
      expect(ArtworkRepairWorkGroupPolicy.sharedSourceKey(
        ArtworkState.READY, 0, 'source-hash'
      )).assertEqual('');
      expect(ArtworkRepairWorkGroupPolicy.sharedSourceKey(
        ArtworkState.READY, 12, ''
      )).assertEqual('');
    });

    it('triesFallbacksUntilOneSourceRepresentativeCompletes', 0, async () => {
      const attempted: Array<number> = [];
      const attempt = await ArtworkRepairWorkGroupPolicy.run(
        [1, 2, 3],
        async (work: number): Promise<ArtworkWorkResult> => {
          attempted.push(work);
          return work < 3 ? result(ArtworkWorkOutcome.FAILED) :
            result(ArtworkWorkOutcome.COMPLETED);
        }
      );
      expect(attempt?.work).assertEqual(3);
      expect(attempt?.result.outcome).assertEqual(ArtworkWorkOutcome.COMPLETED);
      expect(attempt?.attemptCount).assertEqual(3);
      expect(attempted).assertDeepEquals([1, 2, 3]);
    });

    it('stopsFallbacksWhenTheOperationIsCancelled', 0, async () => {
      const attempted: Array<number> = [];
      const attempt = await ArtworkRepairWorkGroupPolicy.run(
        [1, 2],
        async (work: number): Promise<ArtworkWorkResult> => {
          attempted.push(work);
          return result(ArtworkWorkOutcome.SKIPPED);
        }
      );
      expect(attempt?.work).assertEqual(1);
      expect(attempted).assertDeepEquals([1]);
    });
  });
}
