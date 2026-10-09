import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { describe, expect, it } from '@ohos/hypium';
import { ArtworkCache } from '../../../main/ets/library/artwork/ArtworkCache';

const REFERENCED_PATH = 'artwork/cleanup-test/referenced/cover.webp';
const ORPHAN_PATH = 'artwork/cleanup-test/orphan/cover.jpg';
const EMPTY_PATH = 'artwork/cleanup-test/empty';

async function writeFixture(path: string): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try {
    await fs.write(file.fd, new Uint8Array([1, 2, 3, 4]).buffer);
  } finally {
    await fs.close(file);
  }
}

export default function artworkCacheCleanupTest() {
  describe('Artwork cache cleanup', () => {
    it('preservesReferencedFilesAndRemovesOrphansAndEmptyDirectories', 0, async () => {
      const ability = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      const testRoot = `${ability.context.cacheDir}/artwork-cleanup-test`;
      const cache = new ArtworkCache(`${testRoot}/subject`);
      const sentinelCache = new ArtworkCache(`${testRoot}/outside`);
      const sentinelPath = sentinelCache.resolvePath(REFERENCED_PATH);
      const referencedFile = cache.resolvePath(REFERENCED_PATH);
      const orphanFile = cache.resolvePath(ORPHAN_PATH);
      const emptyDirectory = cache.resolvePath(EMPTY_PATH);
      try {
        await fs.mkdir(referencedFile.substring(0, referencedFile.lastIndexOf('/')), true);
        await fs.mkdir(orphanFile.substring(0, orphanFile.lastIndexOf('/')), true);
        await fs.mkdir(emptyDirectory, true);
        await fs.mkdir(sentinelPath.substring(0, sentinelPath.lastIndexOf('/')), true);
        await writeFixture(sentinelPath);
        await writeFixture(referencedFile);
        await writeFixture(orphanFile);
        await cache.cleanupOrphans([REFERENCED_PATH]);
        expect(await fs.access(referencedFile)).assertTrue();
        expect(await fs.access(orphanFile)).assertFalse();
        await cache.cleanupEmptyDirectories();
        expect(await fs.access(referencedFile)).assertTrue();
        expect(await fs.access(emptyDirectory)).assertFalse();
        expect(await fs.access(sentinelPath)).assertTrue();
      } finally {
        await cache.deleteAsync(REFERENCED_PATH);
        await cache.deleteAsync(ORPHAN_PATH);
        await cache.cleanupEmptyDirectories();
        await sentinelCache.deleteAsync(REFERENCED_PATH);
        await sentinelCache.cleanupEmptyDirectories();
      }
    });
  });
}
