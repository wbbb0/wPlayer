import { describe, it, expect } from '@ohos/hypium';
import {
  QueueBuildPhase,
  QueueEntry,
  QueueTrack,
  RepeatMode
} from '../main/ets/playback/model/PlaybackModels';
import { PlaybackQueue } from '../main/ets/playback/queue/PlaybackQueue';

function queueTrack(id: number, title: string): QueueTrack {
  return {
    id: id,
    title: title,
    artistDisplay: '',
    albumDisplay: '',
    durationMs: 0,
    smallArtworkHash: '',
    smallArtworkPath: '',
    largeArtworkHash: '',
    largeArtworkPath: '',
    artworkWidth: 0,
    artworkHeight: 0,
    palettePrimary: '',
    paletteSecondary: '',
    paletteAccent: ''
  };
}

export default function playbackQueueRegressionTest() {
  describe('Playback queue regressions', () => {
    it('keeps sequential next previous and repeat behavior', 0, () => {
      const queue = new PlaybackQueue();
      const items = [queueTrack(1, 'one'), queueTrack(2, 'two'), queueTrack(3, 'three')];

      expect(queue.build(items, 2, false)).assertEqual(QueueBuildPhase.READY);
      expect(queue.current()?.title).assertEqual('two');
      expect(queue.previous()?.title).assertEqual('one');
      expect(queue.previous() === undefined).assertTrue();
      expect(queue.next(RepeatMode.OFF, false)?.title).assertEqual('two');
      expect(queue.next(RepeatMode.OFF, false)?.title).assertEqual('three');
      expect(queue.next(RepeatMode.OFF, true) === undefined).assertTrue();
      expect(queue.next(RepeatMode.ALL, true)?.title).assertEqual('one');
      expect(queue.next(RepeatMode.ONE, true)?.title).assertEqual('one');
    });

    it('selects the first duplicate in current order and leaves cursor on a miss', 0, () => {
      const queue = new PlaybackQueue();
      const items = [
        queueTrack(7, 'first duplicate'),
        queueTrack(8, 'middle'),
        queueTrack(7, 'second duplicate')
      ];

      expect(queue.build(items, 8, false)).assertEqual(QueueBuildPhase.READY);
      expect(queue.select(7)?.title).assertEqual('first duplicate');
      expect(queue.select(99) === undefined).assertTrue();
      expect(queue.current()?.title).assertEqual('first duplicate');
    });

    it('uses the first natural duplicate when building and disabling shuffle', 0, () => {
      const queue = new PlaybackQueue();
      const items = [
        queueTrack(5, 'first duplicate'),
        queueTrack(6, 'middle'),
        queueTrack(5, 'second duplicate')
      ];

      expect(queue.build(items, 5, true)).assertEqual(QueueBuildPhase.READY);
      expect(queue.current()?.title).assertEqual('first duplicate');
      queue.select(6);
      queue.setShuffle(false, 5);
      expect(queue.current()?.title).assertEqual('first duplicate');
    });

    it('keeps insert-next and append order addressable by id', 0, () => {
      const queue = new PlaybackQueue();
      queue.build([queueTrack(1, 'one'), queueTrack(4, 'four')], 1, false);

      queue.insertNext([queueTrack(2, 'two'), queueTrack(3, 'three')]);
      queue.append([queueTrack(5, 'five')]);

      expect(queue.next(RepeatMode.OFF, false)?.title).assertEqual('two');
      expect(queue.next(RepeatMode.OFF, false)?.title).assertEqual('three');
      expect(queue.next(RepeatMode.OFF, false)?.title).assertEqual('four');
      expect(queue.select(5)?.title).assertEqual('five');
      expect(queue.snapshot().currentIndex).assertEqual(4);
    });

    it('discards stale id mappings after failed or empty replacement', 0, () => {
      const queue = new PlaybackQueue();
      queue.build([queueTrack(1, 'one')], 1, false);

      expect(queue.build([queueTrack(2, 'two')], 99, false)).assertEqual(QueueBuildPhase.FAILED);
      expect(queue.size()).assertEqual(0);
      expect(queue.select(1) === undefined).assertTrue();

      expect(queue.build([], 1, false)).assertEqual(QueueBuildPhase.EMPTY);
      expect(queue.current() === undefined).assertTrue();
    });

    it('keeps the current item first when shuffle is enabled', 0, () => {
      const queue = new PlaybackQueue();
      const items = [queueTrack(1, 'one'), queueTrack(2, 'two'), queueTrack(3, 'three')];

      queue.build(items, 2, false);
      queue.setShuffle(true, 2);

      const snapshot = queue.snapshot();
      expect(snapshot.currentIndex).assertEqual(0);
      expect(snapshot.entries[0].track.id).assertEqual(2);
      expect(snapshot.entries.length).assertEqual(3);
    });

    it('keeps stable unique entry identities while shuffling duplicate tracks', 0, () => {
      const queue = new PlaybackQueue();
      const items = [
        queueTrack(5, 'first duplicate'),
        queueTrack(6, 'middle'),
        queueTrack(5, 'second duplicate')
      ];

      queue.build(items, 6, false);
      const before = queue.snapshot();
      queue.setShuffle(true, 6);
      const after = queue.snapshot();
      const beforeEntryIds = before.entries.map((entry: QueueEntry) => entry.queueEntryId)
        .sort((left: number, right: number) => left - right);
      const afterEntryIds = after.entries.map((entry: QueueEntry) => entry.queueEntryId)
        .sort((left: number, right: number) => left - right);

      expect(after.entries[0].track.id).assertEqual(6);
      expect(afterEntryIds.length).assertEqual(3);
      expect(afterEntryIds[0]).assertEqual(beforeEntryIds[0]);
      expect(afterEntryIds[1]).assertEqual(beforeEntryIds[1]);
      expect(afterEntryIds[2]).assertEqual(beforeEntryIds[2]);
      expect(afterEntryIds[0] === afterEntryIds[1]).assertFalse();
      expect(afterEntryIds[1] === afterEntryIds[2]).assertFalse();
    });

    it('reorders a large queue repeatedly without losing entries', 0, () => {
      const queue = new PlaybackQueue();
      const items: Array<QueueTrack> = [];
      for (let index = 0; index < 4096; index += 1) {
        items.push(queueTrack(index + 1, `track ${index + 1}`));
      }

      queue.build(items, 2048, false);
      for (let iteration = 0; iteration < 12; iteration += 1) {
        queue.setShuffle(iteration % 2 === 0, 2048);
      }
      queue.setShuffle(true, 2048);
      const snapshot = queue.snapshot();

      expect(snapshot.entries.length).assertEqual(4096);
      expect(snapshot.currentIndex).assertEqual(0);
      expect(snapshot.entries[0].track.id).assertEqual(2048);
    });
  });
}
