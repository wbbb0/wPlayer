import { describe, expect, it } from '@ohos/hypium';
import {
  PlaylistDetailTarget,
  RepositoryInvalidation,
  RepositoryInvalidationHub,
  RepositoryInvalidationReason,
  RepositoryProjection
} from '../main/ets/library/data/RepositoryInvalidation';

export default function repositoryInvalidationTest() {
  describe('Repository invalidation', () => {
    it('publishes monotonic revisions without duplicate listeners', 0, () => {
      const hub = new RepositoryInvalidationHub();
      const revisions: Array<number> = [];
      const listener = (invalidation: RepositoryInvalidation): void => {
        revisions.push(invalidation.revision);
      };
      hub.addListener(listener);
      hub.addListener(listener);

      hub.publish([RepositoryProjection.PLAYLIST_SUMMARIES],
        RepositoryInvalidationReason.PLAYLIST_CREATED);
      hub.publish([RepositoryProjection.PLAYLIST_SUMMARIES],
        RepositoryInvalidationReason.PLAYLIST_PLAYED);

      expect(revisions.length).assertEqual(2);
      expect(revisions[0]).assertEqual(1);
      expect(revisions[1]).assertEqual(2);
      expect(hub.currentRevision()).assertEqual(2);
    });

    it('deduplicates projections and affected playlist ids', 0, () => {
      const hub = new RepositoryInvalidationHub();
      const invalidation = hub.publish(
        [RepositoryProjection.PLAYLIST_DETAILS, RepositoryProjection.PLAYLIST_DETAILS],
        RepositoryInvalidationReason.PLAYLIST_ITEMS_CHANGED,
        PlaylistDetailTarget.IDS,
        [8, 8, -1, 12]
      );

      expect(invalidation.projections.length).assertEqual(1);
      expect(invalidation.playlistIds.length).assertEqual(2);
      expect(invalidation.affectsPlaylistDetail(8)).assertTrue();
      expect(invalidation.affectsPlaylistDetail(12)).assertTrue();
      expect(invalidation.affectsPlaylistDetail(9)).assertFalse();
    });

    it('isolates listener failures and honors removal', 0, () => {
      const hub = new RepositoryInvalidationHub();
      let delivered = 0;
      const removed = (_invalidation: RepositoryInvalidation): void => {
        delivered += 100;
      };
      hub.addListener((_invalidation: RepositoryInvalidation): void => {
        throw new Error('expected listener failure');
      });
      hub.addListener(removed);
      hub.addListener((_invalidation: RepositoryInvalidation): void => {
        delivered += 1;
      });
      hub.removeListener(removed);

      hub.publish(
        [RepositoryProjection.PLAYLIST_DETAILS],
        RepositoryInvalidationReason.PLAYBACK_COMPLETED,
        PlaylistDetailTarget.ALL
      );

      expect(delivered).assertEqual(1);
    });
  });
}
