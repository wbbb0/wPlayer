import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { LibraryDatabase } from '../../../main/ets/library/data/LibraryDatabase';
import { MusicLibraryImporter } from '../../../main/ets/library/data/MusicLibraryImporter';
import { MusicLibraryMaintenanceQueries } from
  '../../../main/ets/library/data/MusicLibraryMaintenanceQueries';
import { MusicLibraryTrackQueries } from '../../../main/ets/library/data/MusicLibraryTrackQueries';
import {
  ArtworkImportInput,
  LibraryMaintenanceKind
} from '../../../main/ets/library/data/MusicRepositoryTypes';
import { ArtworkSourceIdentityPolicy } from
  '../../../main/ets/library/artwork/ArtworkSourceIdentityPolicy';
import {
  ArtworkPictureType,
  MediaFileCheckCandidate
} from '../../../main/ets/library/model/LibraryModels';

const CONFIG: relationalStore.StoreConfig = {
  name: 'wplayer_artwork_candidate_query.db',
  securityLevel: relationalStore.SecurityLevel.S2,
  allowRebuild: false
};

async function deleteStore(context: common.Context): Promise<void> {
  try {
    await relationalStore.deleteRdbStore(context, CONFIG);
  } catch (_) {
  }
}

export default function musicLibraryArtworkCandidateTest() {
  describe('Music library artwork candidates', () => {
    it('keepsEachTrackBoundToItsExactSourceWhenAssetsAreShared', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const context = ability.context;
      await deleteStore(context);
      const database = new LibraryDatabase(CONFIG);
      try {
        await database.initialize(context);
        const store = database.getStore();
        await store.execute(
          `INSERT INTO artwork_asset(
            id, small_hash, small_path, small_format, large_hash, large_path, large_format,
            ref_count, created_at
          ) VALUES(1, 'small', 'artwork/small.webp', 'image/webp',
            'large', 'artwork/large.webp', 'image/webp', 3, 1)`
        );
        const legacySourceA = 'a'.repeat(64);
        const legacySourceB = 'b'.repeat(64);
        await store.execute(
          `INSERT INTO artwork_source(id, source_hash, asset_id, width, height, created_at)
           VALUES(1, ?, 1, 640, 640, 1),
                 (2, ?, 1, 1024, 768, 1)`,
          [legacySourceA, legacySourceB]
        );
        await store.execute(
          `INSERT INTO media_file(id, uri, display_name, format, artwork_state, created_at, updated_at)
           VALUES(1, 'file://track-a', 'a.mp3', 'mp3', 4, 1, 1),
                 (2, 'file://track-b', 'b.mp3', 'mp3', 4, 1, 1),
                 (3, 'file://track-c', 'c.mp3', 'mp3', 4, 1, 1)`
        );
        await store.execute(
          `INSERT INTO track(id, media_file_id, title, sort_key, primary_artwork_id, created_at, updated_at)
           VALUES(1, 1, 'A', 'a', 1, 1, 1),
                 (2, 2, 'B', 'b', 1, 1, 1),
                 (3, 3, 'C', 'c', 1, 1, 1)`
        );
        await store.execute(
          `INSERT INTO track_artwork(track_id, source_id, asset_id, picture_type, ordinal)
           VALUES(1, 1, 1, 3, 0), (2, 2, 1, 3, 0), (3, 1, 1, 3, 0)`
        );

        const candidates: Array<MediaFileCheckCandidate> =
          await new MusicLibraryTrackQueries(database).getMediaFileCheckCandidates();
        expect(candidates.length).assertEqual(3);
        expect(candidates[0].artworkAssetId).assertEqual(1);
        expect(candidates[0].artworkSourceId).assertEqual(1);
        expect(candidates[0].artworkSourceHash).assertEqual(legacySourceA);
        expect(candidates[0].artworkSourceWidth).assertEqual(640);
        expect(candidates[1].artworkAssetId).assertEqual(1);
        expect(candidates[1].artworkSourceId).assertEqual(2);
        expect(candidates[1].artworkSourceHash).assertEqual(legacySourceB);
        expect(candidates[1].artworkSourceWidth).assertEqual(1024);

        await store.execute("UPDATE media_file SET artwork_state = 5, artwork_last_error = 'failed'");
        await new MusicLibraryImporter(database).markArtworkSourceReferencesReady(1);
        const ready = await store.querySql(
          `SELECT COUNT(*) FROM media_file f JOIN track t ON t.media_file_id = f.id
           JOIN track_artwork ta ON ta.track_id = t.id
           WHERE ta.source_id = 1 AND f.artwork_state = 4 AND f.artwork_last_error = ''`
        );
        try {
          expect(ready.goToNextRow() ? ready.getLong(0) : 0).assertEqual(2);
        } finally {
          ready.close();
        }

        const currentSource = ArtworkSourceIdentityPolicy.fromCurrentDigest('c'.repeat(32));
        const artwork: ArtworkImportInput = {
          metadata: {
            pictureType: ArtworkPictureType.FRONT_COVER,
            mimeType: 'image/jpeg',
            description: '',
            width: 640,
            height: 640,
            colorDepth: 24,
            byteOffset: 0,
            byteLength: 100,
            payloadOffset: 0,
            ordinal: 0,
            unsynchronized: false
          },
          sourceHash: currentSource,
          smallHash: ArtworkSourceIdentityPolicy.cacheKey(currentSource, 3, 'small'),
          smallPath: 'artwork/current.small.webp',
          smallFormat: 'image/webp',
          smallWidth: 256,
          smallHeight: 256,
          smallByteSize: 100,
          largeHash: ArtworkSourceIdentityPolicy.cacheKey(currentSource, 3, 'large'),
          largePath: 'artwork/current.large.webp',
          largeFormat: 'image/webp',
          largeWidth: 640,
          largeHeight: 640,
          largeByteSize: 200,
          encodingVersion: 3,
          primary: true
        };
        const completed = await new MusicLibraryImporter(database).completeArtwork(
          1, 0, 0, [artwork], 1
        );
        expect(completed).assertTrue();
        const migrated = await store.querySql(
          `SELECT COUNT(*), MIN(s.source_hash), COUNT(DISTINCT ta.asset_id)
           FROM track_artwork ta JOIN artwork_source s ON s.id = ta.source_id
           WHERE ta.track_id IN (1, 3)`
        );
        try {
          expect(migrated.goToNextRow()).assertTrue();
          expect(migrated.getLong(0)).assertEqual(2);
          expect(migrated.getString(1)).assertEqual(currentSource);
          expect(migrated.getLong(2)).assertEqual(1);
        } finally {
          migrated.close();
        }
        const maintenance = await new MusicLibraryMaintenanceQueries(database)
          .getLibraryMaintenanceStatus();
        const identityMaintenance = maintenance.items.find((item): boolean =>
          item.kind === LibraryMaintenanceKind.ARTWORK_SOURCE_IDENTITIES
        );
        expect(identityMaintenance?.count).assertEqual(1);
      } finally {
        await database.close();
        await deleteStore(context);
      }
    });
  });
}
