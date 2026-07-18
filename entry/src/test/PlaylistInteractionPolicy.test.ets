import { describe, expect, it } from '@ohos/hypium';
import { CompletedCollectionMode } from '../main/ets/playback/model/PlaybackModels';
import { PlaylistSelectionPolicy } from '../main/ets/playlist/ui/PlaylistSelectionPolicy';
import { CompletedCollectionSettingPolicy } from '../main/ets/settings/CompletedCollectionSettingPolicy';

export default function playlistInteractionPolicyTest() {
  describe('PlaylistInteractionPolicy', () => {
    it('keeps selected track ids in first-seen order', 0, () => {
      const ids = PlaylistSelectionPolicy.uniqueTrackIds([7, 3, 7, 9, 3]);
      expect(ids.length).assertEqual(3);
      expect(ids[0]).assertEqual(7);
      expect(ids[1]).assertEqual(3);
      expect(ids[2]).assertEqual(9);
    });

    it('drops invalid track ids before opening the selection sheet', 0, () => {
      const ids = PlaylistSelectionPolicy.uniqueTrackIds([-1, 0, 4]);
      expect(ids.length).assertEqual(1);
      expect(ids[0]).assertEqual(4);
    });

    it('keeps an empty selection empty', 0, () => {
      expect(PlaylistSelectionPolicy.uniqueTrackIds([]).length).assertEqual(0);
    });

    it('records recently used playlists in most-recent-first order', 0, () => {
      const ids = PlaylistSelectionPolicy.recordRecentTarget([7, 3, 9], 3);
      expect(ids.length).assertEqual(3);
      expect(ids[0]).assertEqual(3);
      expect(ids[1]).assertEqual(7);
      expect(ids[2]).assertEqual(9);
    });

    it('normalizes and caps recently used playlists', 0, () => {
      const ids = PlaylistSelectionPolicy.recordRecentTarget([0, 7, 7, -1, 3, 9], 5);
      expect(ids.length).assertEqual(3);
      expect(ids[0]).assertEqual(5);
      expect(ids[1]).assertEqual(7);
      expect(ids[2]).assertEqual(3);
    });

    it('preserves every supported completed-collection mode', 0, () => {
      expect(CompletedCollectionSettingPolicy.normalize(CompletedCollectionMode.SMART))
        .assertEqual(CompletedCollectionMode.SMART);
      expect(CompletedCollectionSettingPolicy.normalize(CompletedCollectionMode.DEFAULT_ON))
        .assertEqual(CompletedCollectionMode.DEFAULT_ON);
      expect(CompletedCollectionSettingPolicy.normalize(CompletedCollectionMode.DEFAULT_OFF))
        .assertEqual(CompletedCollectionMode.DEFAULT_OFF);
    });

    it('falls back to smart mode for missing or corrupt values', 0, () => {
      expect(CompletedCollectionSettingPolicy.normalize(-1)).assertEqual(CompletedCollectionMode.SMART);
      expect(CompletedCollectionSettingPolicy.normalize(99)).assertEqual(CompletedCollectionMode.SMART);
    });

    it('always provides a visible settings label', 0, () => {
      expect(CompletedCollectionSettingPolicy.label(CompletedCollectionMode.SMART)).assertEqual('智能');
      expect(CompletedCollectionSettingPolicy.label(CompletedCollectionMode.DEFAULT_ON)).assertEqual('默认开启');
      expect(CompletedCollectionSettingPolicy.label(CompletedCollectionMode.DEFAULT_OFF)).assertEqual('默认关闭');
      expect(CompletedCollectionSettingPolicy.label(99)).assertEqual('智能');
    });
  });
}
