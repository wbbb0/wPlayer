import { describe, it, expect } from '@ohos/hypium';
import { ArtworkLayout } from '../../../main/ets/components/artwork/ArtworkLayout';
import { ResourceLeaseRegistry } from '../../../main/ets/playback/artwork/ResourceLeaseRegistry';
import { RequestEpoch } from '../../../main/ets/playback/support/RequestEpoch';
import { DuplicatePolicy } from '../../../main/ets/library/importer/DuplicatePolicy';
import { ImportConcurrencyPolicy } from '../../../main/ets/library/importer/ImportConcurrencyPolicy';
import { ArtworkEncodingPolicy } from '../../../main/ets/library/artwork/ArtworkEncodingPolicy';
import { ImportPreparationPolicy, PreparedItemState } from
  '../../../main/ets/library/importer/ImportPreparationPolicy';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  flattenArtworkPixels,
  probeMediaFile,
  calculateFullFingerprint
} from '../../../main/ets/library/metadata/MediaFileTasks';

class FakeResource {
  released: number = 0;
}

export default function riskRegressionTest() {
  describe('RiskRegression', () => {
    it('containsLandscapeAndPortraitArtwork', 0, () => {
      const landscape = ArtworkLayout.containedSize(768, 432, 286, 286);
      const portrait = ArtworkLayout.containedSize(540, 768, 286, 286);
      expect(landscape.width).assertEqual(286);
      expect(Math.round(landscape.height)).assertEqual(161);
      expect(Math.round(portrait.width)).assertEqual(201);
      expect(portrait.height).assertEqual(286);
    });

    it('holdsArtworkUntilLeaseRelease', 0, () => {
      const registry = new ResourceLeaseRegistry<FakeResource>((resource: FakeResource) => {
        resource.released += 1;
      });
      const resource = new FakeResource();
      registry.acquire(resource);
      registry.requestRelease(resource);
      expect(resource.released).assertEqual(0);
      registry.release(resource);
      expect(resource.released).assertEqual(1);
    });

    it('invalidatesStalePlaybackEpoch', 0, () => {
      const epoch = new RequestEpoch();
      const first = epoch.begin();
      epoch.invalidate();
      expect(epoch.isCurrent(first)).assertFalse();
      const second = epoch.begin();
      expect(epoch.isCurrent(second)).assertTrue();
    });

    it('requiresFullFingerprintForDuplicateProof', 0, () => {
      expect(DuplicatePolicy.isConfirmedDuplicate('quick', 'quick', 'full-a', 'full-b')).assertFalse();
      expect(DuplicatePolicy.isConfirmedDuplicate('quick', 'quick', 'full-a', 'full-a')).assertTrue();
      expect(DuplicatePolicy.isConfirmedDuplicate('quick-a', 'quick-b', 'full-a', 'full-a')).assertTrue();
    });

    it('calculatesFullFingerprintOnlyForCandidates', 0, () => {
      expect(ImportConcurrencyPolicy.needsFullFingerprint(0, 1)).assertFalse();
      expect(ImportConcurrencyPolicy.needsFullFingerprint(1, 1)).assertTrue();
      expect(ImportConcurrencyPolicy.needsFullFingerprint(0, 2)).assertTrue();
      expect(ImportConcurrencyPolicy.FILE_PROBE_CONCURRENCY).assertEqual(3);
    });

    it('usesJpegForPersistentArtworkVariants', 0, () => {
      expect(ArtworkEncodingPolicy.MIME_TYPE).assertEqual('image/jpeg');
      expect(ArtworkEncodingPolicy.EXTENSION).assertEqual('jpg');
      expect(ArtworkEncodingPolicy.QUALITY).assertLarger(0);
      expect(ArtworkEncodingPolicy.QUALITY).assertLess(101);
    });

    it('classifiesEarlyDuplicateWithoutInputAsDuplicate', 0, () => {
      expect(ImportPreparationPolicy.classify(false, true, false))
        .assertEqual(PreparedItemState.DUPLICATE);
    });

    it('probesMediaAndFlattensArtworkOffMainThread', 0, async () => {
      const path = '/data/storage/el2/base/files/taskpool-probe.mp3';
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        const minimalId3 = new Uint8Array([
          0x49, 0x44, 0x33, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00
        ]);
        fs.writeSync(file.fd, minimalId3.buffer);
      } finally {
        fs.closeSync(file);
      }
      try {
        const probe = await probeMediaFile(path);
        expect(probe.fileSize).assertEqual(11);
        expect(probe.quickFingerprint.length).assertEqual(64);
        expect(probe.metadata.rawTags.size).assertEqual(0);

        const bgraBuffer = new ArrayBuffer(4);
        new Uint8Array(bgraBuffer).set([0, 0, 255, 255]);
        const rgba = new Uint8Array(await flattenArtworkPixels(bgraBuffer, 1, 1, false));
        expect(rgba[0]).assertEqual(255);
        expect(rgba[1]).assertEqual(0);
        expect(rgba[2]).assertEqual(0);
        expect(rgba[3]).assertEqual(255);
      } finally {
        fs.unlinkSync(path);
      }
    });

    it('fullFingerprintIncludesBytesOutsideQuickFingerprintWindows', 0, async () => {
      const firstPath = '/data/storage/el2/base/files/full-hash-a.bin';
      const secondPath = '/data/storage/el2/base/files/full-hash-b.bin';
      const firstBytes = new Uint8Array(2 * 1024 * 1024);
      const secondBytes = new Uint8Array(2 * 1024 * 1024);
      firstBytes[1024 * 1024] = 1;
      secondBytes[1024 * 1024] = 2;
      const firstFile = fs.openSync(firstPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      const secondFile = fs.openSync(secondPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(firstFile.fd, firstBytes.buffer);
        fs.writeSync(secondFile.fd, secondBytes.buffer);
      } finally {
        fs.closeSync(firstFile);
        fs.closeSync(secondFile);
      }
      try {
        const hashes = await Promise.all([
          calculateFullFingerprint(firstPath),
          calculateFullFingerprint(secondPath)
        ]);
        expect(hashes[0] === hashes[1]).assertFalse();
      } finally {
        fs.unlinkSync(firstPath);
        fs.unlinkSync(secondPath);
      }
    });
  });
}
