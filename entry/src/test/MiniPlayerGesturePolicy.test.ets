import { describe, expect, it } from '@ohos/hypium';
import {
  MiniPlayerClickSuppressor
} from '../main/ets/components/player/PlayerMotion';
import {
  MiniPlayerTrackPagerPolicy,
  MiniPlayerTrackPageTarget
} from '../main/ets/components/player/MiniPlayerTrackPagerPolicy';
import {
  QueueEntry,
  QueueTrack,
  RepeatMode
} from '../main/ets/playback/model/PlaybackModels';

function queueEntry(queueEntryId: number, trackId: number = queueEntryId): QueueEntry {
  const track: QueueTrack = {
    id: trackId,
    title: `Track ${trackId}`,
    artistDisplay: `Artist ${trackId}`,
    albumDisplay: '',
    durationMs: 1000,
    smallArtworkHash: '',
    smallArtworkPath: '',
    largeArtworkHash: '',
    largeArtworkPath: '',
    artworkWidth: 0,
    artworkHeight: 0,
    palettePrimary: '#FF000000',
    paletteSecondary: '#FF000000',
    paletteAccent: '#FF000000'
  };
  return { queueEntryId: queueEntryId, track: track };
}

export default function miniPlayerGesturePolicyTest() {
  describe('Mini player gesture policy', () => {
    it('suppresses only the click immediately following a recognized pan', 0, () => {
      const suppressor = new MiniPlayerClickSuppressor();

      expect(suppressor.consumeClickSuppression()).assertFalse();
      suppressor.markPanRecognized();
      expect(suppressor.consumeClickSuppression()).assertTrue();
      expect(suppressor.consumeClickSuppression()).assertFalse();
    });

    it('projects adjacent entries from active playback order by queue identity', 0, () => {
      const entries = [queueEntry(41, 9), queueEntry(17, 9), queueEntry(63, 9)];
      const window = MiniPlayerTrackPagerPolicy.window(entries, 1, RepeatMode.OFF);

      expect(window.previous?.queueEntryId).assertEqual(41);
      expect(window.current?.queueEntryId).assertEqual(17);
      expect(window.next?.queueEntryId).assertEqual(63);
    });

    it('wraps only the next edge when repeat-all matches runtime navigation', 0, () => {
      const entries = [queueEntry(1), queueEntry(2)];
      const repeatAll = MiniPlayerTrackPagerPolicy.window(entries, 1, RepeatMode.ALL);
      const repeatOff = MiniPlayerTrackPagerPolicy.window(entries, 1, RepeatMode.OFF);

      expect(repeatAll.next?.queueEntryId).assertEqual(1);
      expect(repeatOff.next).assertUndefined();
      expect(MiniPlayerTrackPagerPolicy.window(entries, 0, RepeatMode.ALL).previous)
        .assertUndefined();
    });

    it('uses real page travel when a neighbor exists and resistance only at edges', 0, () => {
      expect(MiniPlayerTrackPagerPolicy.dragOffset(-120, 180, true, true)).assertEqual(-120);
      expect(MiniPlayerTrackPagerPolicy.dragOffset(-240, 180, true, true)).assertLarger(-240);
      expect(MiniPlayerTrackPagerPolicy.dragOffset(-120, 180, true, false)).assertLarger(-120);
    });

    it('settles to an available adjacent page after the fixed completion distance', 0, () => {
      expect(MiniPlayerTrackPagerPolicy.target(-47, true, true))
        .assertEqual(MiniPlayerTrackPageTarget.CURRENT);
      expect(MiniPlayerTrackPagerPolicy.target(-48, true, true))
        .assertEqual(MiniPlayerTrackPageTarget.NEXT);
      expect(MiniPlayerTrackPagerPolicy.target(48, true, true))
        .assertEqual(MiniPlayerTrackPageTarget.PREVIOUS);
      expect(MiniPlayerTrackPagerPolicy.target(80, false, true))
        .assertEqual(MiniPlayerTrackPageTarget.CURRENT);
      expect(MiniPlayerTrackPagerPolicy.targetOffset(MiniPlayerTrackPageTarget.NEXT, 180))
        .assertEqual(-180);
    });

    it('rebases an interrupted release onto the committed entry without moving its displayed frame', 0, () => {
      const window = MiniPlayerTrackPagerPolicy.window(
        [queueEntry(10), queueEntry(20), queueEntry(30)], 1, RepeatMode.OFF
      );
      expect(MiniPlayerTrackPagerPolicy.rebaseOffset(window, 30, -120, 180)).assertEqual(60);
      expect(MiniPlayerTrackPagerPolicy.rebaseOffset(window, 10, 120, 180)).assertEqual(-60);
      expect(MiniPlayerTrackPagerPolicy.rebaseOffset(window, 20, 30, 180)).assertEqual(30);
      expect(MiniPlayerTrackPagerPolicy.rebaseOffset(window, 99, 30, 180)).assertEqual(0);
      const wrapped = MiniPlayerTrackPagerPolicy.window([queueEntry(10), queueEntry(20)], 1, RepeatMode.ALL);
      expect(MiniPlayerTrackPagerPolicy.rebaseOffset(wrapped, 10, 120, 180)).assertEqual(-60);
      expect(MiniPlayerTrackPagerPolicy.rebaseOffset(wrapped, 10, -120, 180)).assertEqual(60);
    });

    it('rejects a settled target after playback has left the frozen source entry', 0, () => {
      const window = MiniPlayerTrackPagerPolicy.window(
        [queueEntry(10), queueEntry(20), queueEntry(30)],
        1,
        RepeatMode.OFF
      );

      expect(MiniPlayerTrackPagerPolicy.commitEntry(
        window,
        MiniPlayerTrackPageTarget.NEXT,
        20
      )?.queueEntryId).assertEqual(30);
      expect(MiniPlayerTrackPagerPolicy.commitEntry(
        window,
        MiniPlayerTrackPageTarget.NEXT,
        30
      )).assertUndefined();
    });
  });
}
