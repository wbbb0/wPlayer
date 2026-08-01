import { describe, it, expect } from '@ohos/hypium';
import {
  QueueBuildPhase,
  QueueEntry,
  QueueEntryPresentation,
  QueueTrackDataSource,
  QueueTrack,
  PlayerStore,
  RepeatMode
} from '../main/ets/playback/model/PlaybackModels';

class QueueDataListener implements DataChangeListener {
  operations: Array<DataOperation> = [];
  batches: Array<Array<DataOperation>> = [];

  onDataReloaded(): void {}
  onDataAdded(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataChange(_index: number): void {}
  onDatasetChange(dataOperations: Array<DataOperation>): void {
    this.operations = dataOperations;
    this.batches.push(dataOperations);
  }
}
import {
  PlaybackQueue,
  PlaybackQueueStateItem
} from '../main/ets/playback/queue/PlaybackQueue';

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

    it('restores exact order and selects a later duplicate by position', 0, () => {
      const queue = new PlaybackQueue();
      const items = [
        queueTrack(1, 'first duplicate'),
        queueTrack(2, 'middle'),
        queueTrack(1, 'second duplicate')
      ];

      expect(queue.restore(items, [0, 1, 2], 2)).assertEqual(QueueBuildPhase.READY);
      expect(queue.current()?.title).assertEqual('second duplicate');
      const snapshot = queue.playbackSnapshot();
      expect(snapshot.entries[0].track.title).assertEqual('first duplicate');
      expect(snapshot.entries[1].track.title).assertEqual('middle');
      expect(snapshot.entries[2].track.title).assertEqual('second duplicate');
    });

    it('publishes only changed queue rows when the playback cursor moves', 0, () => {
      const source = new QueueTrackDataSource();
      const listener = new QueueDataListener();
      source.registerDataChangeListener(listener);
      source.replace([
        { queueEntryId: 1, track: queueTrack(1, 'one') },
        { queueEntryId: 2, track: queueTrack(2, 'two') },
        { queueEntryId: 3, track: queueTrack(3, 'three') }
      ]);

      source.notifyChanged([0, 1, 1, -1]);

      expect(listener.operations.length).assertEqual(2);
      expect(listener.operations[0].type).assertEqual(DataOperationType.CHANGE);
      expect(listener.operations[0].index).assertEqual(0);
      expect(listener.operations[1].type).assertEqual(DataOperationType.CHANGE);
      expect(listener.operations[1].index).assertEqual(1);
    });

    it('publishes no operations for an identical queue snapshot', 0, () => {
      const store = new PlayerStore();
      const listener = new QueueDataListener();
      const entries: Array<QueueEntry> = [
        { queueEntryId: 1, track: queueTrack(7, 'first duplicate') },
        { queueEntryId: 2, track: queueTrack(7, 'second duplicate') }
      ];
      store.queueDataSource.registerDataChangeListener(listener);
      store.applyQueueSnapshot(entries, 0);
      listener.batches = [];

      store.applyQueueSnapshot(entries, 0);

      expect(listener.batches.length).assertEqual(0);
    });

    it('projects a stable-entry permutation through disjoint exchange layers', 0, () => {
      const source = new QueueTrackDataSource();
      const listener = new QueueDataListener();
      const scheduled: Array<() => void> = [];
      const original: Array<QueueEntry> = [
        { queueEntryId: 10, track: queueTrack(7, 'first duplicate') },
        { queueEntryId: 11, track: queueTrack(8, 'middle') },
        { queueEntryId: 12, track: queueTrack(7, 'second duplicate') }
      ];
      const reordered: Array<QueueEntry> = [original[2], original[0], original[1]];
      source.registerDataChangeListener(listener);
      source.replace(original);
      source.setFrameScheduler((task: () => void): void => {
        scheduled.push(task);
      });
      listener.batches = [];

      source.applySnapshot(reordered, 0, [0, 2], (_index: number): void => {});
      expect(listener.batches.length).assertEqual(1);
      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.EXCHANGE);
      expect(scheduled.length).assertEqual(1);
      scheduled[0]();

      expect(listener.batches.length).assertEqual(2);
      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.EXCHANGE);
      expect(source.snapshot().map((entry: QueueEntry): number => entry.queueEntryId).join(','))
        .assertEqual('12,10,11');
    });

    it('keeps a newer cursor update across the second permutation frame', 0, () => {
      const store = new PlayerStore();
      const listener = new QueueDataListener();
      const scheduled: Array<() => void> = [];
      const focused: Array<number> = [];
      const original: Array<QueueEntry> = [
        { queueEntryId: 10, track: queueTrack(1, 'one') },
        { queueEntryId: 11, track: queueTrack(2, 'two') },
        { queueEntryId: 12, track: queueTrack(3, 'three') }
      ];
      store.queueDataSource.registerDataChangeListener(listener);
      store.applyQueueSnapshot(original, 0);
      store.queueDataSource.setFrameScheduler((task: () => void): void => {
        scheduled.push(task);
      });
      store.addQueueIndexListener((index: number): void => {
        focused.push(index);
      });

      store.applyQueueSnapshot([original[2], original[0], original[1]], 0);
      expect((store.queueDataSource.getData(0) as QueueEntryPresentation).entry.queueEntryId)
        .assertEqual(12);
      expect((store.queueDataSource.getData(0) as QueueEntryPresentation).isActive()).assertTrue();
      store.setQueueCurrentIndex(1, original[0].queueEntryId);
      scheduled[0]();

      expect(store.queueCurrentIndex).assertEqual(1);
      expect(focused.join(',')).assertEqual('1');
      expect((store.queueDataSource.getData(1) as QueueEntryPresentation).entry.queueEntryId)
        .assertEqual(10);
      expect((store.queueDataSource.getData(1) as QueueEntryPresentation).isActive()).assertTrue();
    });

    it('reloads queue rows when the entry identity set changes', 0, () => {
      const source = new QueueTrackDataSource();
      const listener = new QueueDataListener();
      source.registerDataChangeListener(listener);
      source.replace([{ queueEntryId: 1, track: queueTrack(1, 'one') }]);

      source.applySnapshot([
        { queueEntryId: 1, track: queueTrack(1, 'one') },
        { queueEntryId: 2, track: queueTrack(2, 'two') }
      ], 0, [0], (_index: number): void => {});

      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.RELOAD);
    });

    it('reloads queue rows when entry identities are not unique', 0, () => {
      const source = new QueueTrackDataSource();
      const listener = new QueueDataListener();
      source.registerDataChangeListener(listener);
      source.replace([
        { queueEntryId: 1, track: queueTrack(1, 'one') },
        { queueEntryId: 2, track: queueTrack(2, 'two') }
      ]);

      source.applySnapshot([
        { queueEntryId: 1, track: queueTrack(1, 'one') },
        { queueEntryId: 1, track: queueTrack(2, 'duplicate identity') }
      ], 0, [], (_index: number): void => {});

      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.RELOAD);
    });

    it('publishes only old and new active rows when queue order is unchanged', 0, () => {
      const store = new PlayerStore();
      const listener = new QueueDataListener();
      const entries: Array<QueueEntry> = [
        { queueEntryId: 1, track: queueTrack(1, 'one') },
        { queueEntryId: 2, track: queueTrack(2, 'two') },
        { queueEntryId: 3, track: queueTrack(3, 'three') }
      ];
      store.queueDataSource.registerDataChangeListener(listener);
      store.applyQueueSnapshot(entries, 0);

      store.applyQueueSnapshot(entries, 2);

      expect(listener.operations.length).assertEqual(2);
      expect(listener.operations[0].type).assertEqual(DataOperationType.CHANGE);
      expect(listener.operations[0].index).assertEqual(0);
      expect(listener.operations[1].type).assertEqual(DataOperationType.CHANGE);
      expect(listener.operations[1].index).assertEqual(2);
    });

    it('selects an exact duplicate queue entry and leaves cursor on a miss', 0, () => {
      const queue = new PlaybackQueue();
      const items = [
        queueTrack(7, 'first duplicate'),
        queueTrack(8, 'middle'),
        queueTrack(7, 'second duplicate')
      ];

      expect(queue.build(items, 8, false)).assertEqual(QueueBuildPhase.READY);
      const duplicateEntries = queue.playbackSnapshot().entries;
      expect(queue.selectEntry(duplicateEntries[2].queueEntryId)?.title).assertEqual('second duplicate');
      expect(queue.currentEntryId()).assertEqual(duplicateEntries[2].queueEntryId);
      expect(queue.selectEntry(99) === undefined).assertTrue();
      expect(queue.current()?.title).assertEqual('second duplicate');
    });

    it('keeps the exact duplicate entry current while toggling shuffle', 0, () => {
      const queue = new PlaybackQueue();
      const items = [
        queueTrack(5, 'first duplicate'),
        queueTrack(6, 'middle'),
        queueTrack(5, 'second duplicate')
      ];

      expect(queue.restore(items, [0, 1, 2], 2)).assertEqual(QueueBuildPhase.READY);
      const currentEntryId = queue.playbackSnapshot().entries[2].queueEntryId;
      queue.setShuffle(true);
      expect(queue.current()?.title).assertEqual('second duplicate');
      expect(queue.playbackSnapshot().entries[0].queueEntryId).assertEqual(currentEntryId);
      expect(queue.displaySnapshot().entries[2].queueEntryId).assertEqual(currentEntryId);
      expect(queue.displaySnapshot().currentIndex).assertEqual(2);
      queue.setShuffle(false);
      expect(queue.current()?.title).assertEqual('second duplicate');
      expect(queue.playbackSnapshot().currentIndex).assertEqual(2);
    });

    it('keeps insert-next and append order addressable by id', 0, () => {
      const queue = new PlaybackQueue();
      queue.build([queueTrack(1, 'one'), queueTrack(4, 'four')], 1, false);

      queue.insertNext([queueTrack(2, 'two'), queueTrack(3, 'three')]);
      queue.append([queueTrack(5, 'five')]);

      expect(queue.next(RepeatMode.OFF, false)?.title).assertEqual('two');
      expect(queue.next(RepeatMode.OFF, false)?.title).assertEqual('three');
      expect(queue.next(RepeatMode.OFF, false)?.title).assertEqual('four');
      const fiveEntryId = queue.playbackSnapshot().entries[4].queueEntryId;
      expect(queue.selectEntry(fiveEntryId)?.title).assertEqual('five');
      expect(queue.playbackSnapshot().currentIndex).assertEqual(4);
    });

    it('discards stale id mappings after failed or empty replacement', 0, () => {
      const queue = new PlaybackQueue();
      queue.build([queueTrack(1, 'one')], 1, false);

      expect(queue.build([queueTrack(2, 'two')], 99, false)).assertEqual(QueueBuildPhase.FAILED);
      expect(queue.size()).assertEqual(0);
      expect(queue.selectEntry(1) === undefined).assertTrue();

      expect(queue.build([], 1, false)).assertEqual(QueueBuildPhase.EMPTY);
      expect(queue.current() === undefined).assertTrue();
    });

    it('keeps the current item first when shuffle is enabled', 0, () => {
      const queue = new PlaybackQueue();
      const items = [queueTrack(1, 'one'), queueTrack(2, 'two'), queueTrack(3, 'three')];

      queue.build(items, 2, false);
      queue.setShuffle(true);

      const snapshot = queue.playbackSnapshot();
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
      const before = queue.playbackSnapshot();
      queue.setShuffle(true);
      const after = queue.playbackSnapshot();
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

    it('projects shuffled playback order without reloading the queue', 0, () => {
      const queue = new PlaybackQueue();
      const store = new PlayerStore();
      const listener = new QueueDataListener();
      const items = [queueTrack(1, 'one'), queueTrack(2, 'two'), queueTrack(3, 'three')];

      queue.build(items, 2, false);
      const before = queue.playbackSnapshot();
      store.queueDataSource.registerDataChangeListener(listener);
      store.applyQueueSnapshot(before.entries, before.currentIndex);
      listener.operations = [];
      const scheduled: Array<() => void> = [];
      store.queueDataSource.setFrameScheduler((task: () => void): void => {
        scheduled.push(task);
      });
      queue.setShuffle(true);
      const after = queue.playbackSnapshot();
      store.applyQueueSnapshot(after.entries, after.currentIndex);
      scheduled.forEach((task: () => void): void => task());

      expect(after.entries[0].track.id).assertEqual(2);
      expect(after.entries.map((entry: QueueEntry): number => entry.queueEntryId).sort().join(','))
        .assertEqual(before.entries.map((entry: QueueEntry): number => entry.queueEntryId).sort().join(','));
      expect(after.currentIndex).assertEqual(0);
      expect(queue.currentPlaybackPosition()).assertEqual(0);
      expect(queue.current()?.id).assertEqual(2);
      expect(listener.batches.some((batch: Array<DataOperation>): boolean =>
        batch.some((operation: DataOperation): boolean =>
          operation.type === DataOperationType.EXCHANGE))).assertTrue();
      expect(listener.operations.some((operation: DataOperation): boolean =>
        operation.type === DataOperationType.RELOAD)).assertFalse();
    });

    it('restores base order and shuffled playback order as separate state', 0, () => {
      const tracks = [queueTrack(1, 'one'), queueTrack(2, 'two'), queueTrack(3, 'three')];
      const queue = new PlaybackQueue();
      queue.build(tracks, 2, false);
      queue.setShuffle(true);
      const before = queue.playbackSnapshot();
      const state = queue.stateSnapshot();
      const restored = new PlaybackQueue();

      expect(restored.restore(
        tracks,
        state.items.map((item: PlaybackQueueStateItem): number => item.playbackPosition),
        state.currentPosition
      )).assertEqual(QueueBuildPhase.READY);

      expect(restored.playbackSnapshot().entries.map((entry: QueueEntry): number => entry.track.id).join(','))
        .assertEqual(before.entries.map((entry: QueueEntry): number => entry.track.id).join(','));
      restored.setShuffle(false);
      expect(restored.playbackSnapshot().entries.map((entry: QueueEntry): number => entry.track.id).join(','))
        .assertEqual('1,2,3');
      expect(restored.current()?.id).assertEqual(2);
    });

    it('reorders a large queue repeatedly without losing entries', 0, () => {
      const queue = new PlaybackQueue();
      const items: Array<QueueTrack> = [];
      for (let index = 0; index < 4096; index += 1) {
        items.push(queueTrack(index + 1, `track ${index + 1}`));
      }

      queue.build(items, 2048, false);
      for (let iteration = 0; iteration < 12; iteration += 1) {
        queue.setShuffle(iteration % 2 === 0);
      }
      queue.setShuffle(true);
      const snapshot = queue.playbackSnapshot();

      expect(snapshot.entries.length).assertEqual(4096);
      expect(snapshot.currentIndex).assertEqual(0);
      expect(snapshot.entries[0].track.id).assertEqual(2048);
      const displaySnapshot = queue.displaySnapshot();
      expect(displaySnapshot.entries.length).assertEqual(4096);
      expect(displaySnapshot.entries[0].track.id).assertEqual(1);
      expect(displaySnapshot.currentIndex).assertEqual(2047);
    });

    it('preserves base order through shuffled insertion append and removal', 0, () => {
      const queue = new PlaybackQueue();
      queue.build([queueTrack(1, 'one'), queueTrack(2, 'two'), queueTrack(3, 'three')], 2, false);
      queue.setShuffle(true);

      queue.insertNext([queueTrack(4, 'four')]);
      queue.append([queueTrack(5, 'five')]);
      const three = queue.playbackSnapshot().entries.filter(
        (entry: QueueEntry): boolean => entry.track.id === 3)[0];
      queue.removeEntries(three === undefined ? [] : [three.queueEntryId]);
      queue.setShuffle(false);

      const natural = queue.playbackSnapshot();
      expect(natural.entries.map((entry: QueueEntry): number => entry.track.id).join(','))
        .assertEqual('1,2,4,5');
      expect(queue.current()?.id).assertEqual(2);
    });

    it('selects the next playback entry when the shuffled current entry is removed', 0, () => {
      const queue = new PlaybackQueue();
      queue.restore(
        [queueTrack(1, 'one'), queueTrack(2, 'two'), queueTrack(3, 'three')],
        [1, 0, 2],
        0
      );
      const currentEntryId = queue.playbackSnapshot().entries[0].queueEntryId;

      const result = queue.removeEntries([currentEntryId]);

      expect(result.removedCurrent).assertTrue();
      expect(result.current?.id).assertEqual(1);
      queue.setShuffle(false);
      expect(queue.playbackSnapshot().entries.map((entry: QueueEntry): number => entry.track.id).join(','))
        .assertEqual('1,3');
    });

    it('selects the next survivor when removing the current and earlier entries together', 0, () => {
      const queue = new PlaybackQueue();
      queue.restore(
        [
          queueTrack(1, 'one'),
          queueTrack(2, 'two'),
          queueTrack(3, 'three'),
          queueTrack(4, 'four'),
          queueTrack(5, 'five')
        ],
        [0, 1, 2, 3, 4],
        2
      );
      const entries = queue.playbackSnapshot().entries;

      const result = queue.removeEntries([entries[1].queueEntryId, entries[2].queueEntryId]);

      expect(result.removedCurrent).assertTrue();
      expect(result.current?.id).assertEqual(4);
      expect(queue.currentPlaybackPosition()).assertEqual(1);
    });

    it('falls back to the previous survivor when current and later entries are removed', 0, () => {
      const queue = new PlaybackQueue();
      queue.restore(
        [queueTrack(1, 'one'), queueTrack(2, 'two'), queueTrack(3, 'three')],
        [0, 1, 2],
        1
      );
      const entries = queue.playbackSnapshot().entries;

      const result = queue.removeEntries([entries[1].queueEntryId, entries[2].queueEntryId]);

      expect(result.removedCurrent).assertTrue();
      expect(result.current?.id).assertEqual(1);
      expect(queue.currentPlaybackPosition()).assertEqual(0);
    });

    it('rejects an invalid restored playback permutation', 0, () => {
      const queue = new PlaybackQueue();
      const items = [queueTrack(1, 'one'), queueTrack(2, 'two')];

      expect(queue.restore(items, [0, 0], 0)).assertEqual(QueueBuildPhase.FAILED);
      expect(queue.size()).assertEqual(0);
      expect(queue.restore(items, [0, 2], 0)).assertEqual(QueueBuildPhase.FAILED);
    });

    it('updates every queued track that shares the refreshed artwork', 0, () => {
      const queue = new PlaybackQueue();
      const first = queueTrack(1, 'first');
      const second = queueTrack(2, 'second');
      const other = queueTrack(3, 'other');
      first.largeArtworkHash = 'shared-artwork';
      second.largeArtworkHash = 'shared-artwork';
      other.largeArtworkHash = 'other-artwork';
      first.palettePrimary = '#FF111111';
      second.palettePrimary = '#FF111111';
      other.palettePrimary = '#FF222222';
      queue.build([first, second, other], 1, false);

      const updatedIndices = queue.updateArtworkPalette(
        first,
        '#FF334455',
        '#FF667788',
        '#FF99AABB'
      );
      const snapshot = queue.playbackSnapshot();

      expect(updatedIndices.length).assertEqual(2);
      expect(updatedIndices[0]).assertEqual(0);
      expect(updatedIndices[1]).assertEqual(1);
      expect(snapshot.entries[0].track.palettePrimary).assertEqual('#FF334455');
      expect(snapshot.entries[1].track.palettePrimary).assertEqual('#FF334455');
      expect(snapshot.entries[1].track.paletteSecondary).assertEqual('#FF667788');
      expect(snapshot.entries[1].track.paletteAccent).assertEqual('#FF99AABB');
      expect(snapshot.entries[2].track.palettePrimary).assertEqual('#FF222222');
    });

    it('returns playback-order row indices for artwork updates', 0, () => {
      const queue = new PlaybackQueue();
      const first = queueTrack(1, 'first');
      const second = queueTrack(2, 'second');
      const other = queueTrack(3, 'other');
      first.largeArtworkHash = 'shared-artwork';
      second.largeArtworkHash = 'shared-artwork';
      other.largeArtworkHash = 'other-artwork';

      queue.restore([first, second, other], [2, 0, 1], 0);
      const updatedIndices = queue.updateArtworkPalette(
        first,
        '#FF334455',
        '#FF667788',
        '#FF99AABB'
      );

      expect(updatedIndices.join(',')).assertEqual('0,2');
      expect(queue.displaySnapshot().currentIndex).assertEqual(1);
      expect(queue.currentPlaybackPosition()).assertEqual(0);
    });
  });
}
