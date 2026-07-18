import { describe, expect, it } from '@ohos/hypium';
import {
  PlaylistItemInput,
  PlaylistItemSource,
  PlaylistKind
} from '../main/ets/library/model/LibraryModels';
import { PlaylistPolicy } from '../main/ets/playlist/data/PlaylistPolicy';

function item(trackId: number, source: PlaylistItemSource = PlaylistItemSource.MANUAL): PlaylistItemInput {
  return { trackId: trackId, source: source };
}

export default function playlistPolicyTest() {
  describe('PlaylistPolicy', () => {
    it('protects only the completed-history entity', 0, () => {
      expect(PlaylistPolicy.canCreate(PlaylistKind.USER)).assertTrue();
      expect(PlaylistPolicy.canRename(PlaylistKind.USER)).assertTrue();
      expect(PlaylistPolicy.canDelete(PlaylistKind.USER)).assertTrue();
      expect(PlaylistPolicy.canCreate(PlaylistKind.COMPLETED_HISTORY)).assertFalse();
      expect(PlaylistPolicy.canRename(PlaylistKind.COMPLETED_HISTORY)).assertFalse();
      expect(PlaylistPolicy.canDelete(PlaylistKind.COMPLETED_HISTORY)).assertFalse();
    });

    it('allows full item editing in every playlist kind', 0, () => {
      expect(PlaylistPolicy.canEditItems(PlaylistKind.USER)).assertTrue();
      expect(PlaylistPolicy.canEditItems(PlaylistKind.COMPLETED_HISTORY)).assertTrue();
    });

    it('normalizes names for stable conflict detection', 0, () => {
      expect(PlaylistPolicy.normalizeName('  Road   Trip ')).assertEqual('road trip');
      expect(PlaylistPolicy.requireName('  Road   Trip ')).assertEqual('Road Trip');
    });

    it('rejects blank playlist names', 0, () => {
      let rejected = false;
      try {
        PlaylistPolicy.requireName(' \t ');
      } catch (_) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    it('plans merge without existing or repeated tracks', 0, () => {
      const plan = PlaylistPolicy.planMerge(
        [1, 2],
        [item(2, PlaylistItemSource.IMPORT), item(3), item(3), item(4)]
      );
      expect(plan.items.length).assertEqual(2);
      expect(plan.items[0].trackId).assertEqual(3);
      expect(plan.items[1].trackId).assertEqual(4);
      expect(plan.alreadyPresent).assertEqual(1);
      expect(plan.duplicateInput).assertEqual(1);
    });

    it('plans replacement in first-seen order', 0, () => {
      const plan = PlaylistPolicy.planReplace([item(7), item(4), item(7), item(9)]);
      expect(plan.items.length).assertEqual(3);
      expect(plan.items[0].trackId).assertEqual(7);
      expect(plan.items[1].trackId).assertEqual(4);
      expect(plan.items[2].trackId).assertEqual(9);
      expect(plan.duplicateInput).assertEqual(1);
    });

    it('keeps an all-existing merge as a no-op', 0, () => {
      const plan = PlaylistPolicy.planMerge([2, 5], [item(5), item(2), item(5)]);
      expect(plan.items.length).assertEqual(0);
      expect(plan.alreadyPresent).assertEqual(2);
      expect(plan.duplicateInput).assertEqual(1);
    });

    it('allows an empty replacement plan for explicit clearing', 0, () => {
      const plan = PlaylistPolicy.planReplace([]);
      expect(plan.items.length).assertEqual(0);
      expect(plan.alreadyPresent).assertEqual(0);
      expect(plan.duplicateInput).assertEqual(0);
    });

    it('accepts only complete duplicate-free reorders', 0, () => {
      expect(PlaylistPolicy.isCompleteReorder([1, 2, 3], [3, 1, 2])).assertTrue();
      expect(PlaylistPolicy.isCompleteReorder([1, 2, 3], [1, 2])).assertFalse();
      expect(PlaylistPolicy.isCompleteReorder([1, 2, 3], [1, 2, 2])).assertFalse();
      expect(PlaylistPolicy.isCompleteReorder([1, 2, 3], [1, 2, 4])).assertFalse();
    });
  });
}
