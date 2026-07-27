import { describe, expect, it } from '@ohos/hypium';
import {
  DuplicateCandidate,
  TrackImportInput
} from '../main/ets/library/data/MusicRepository';
import {
  MediaFormat,
  ParsedMetadata
} from '../main/ets/library/model/LibraryModels';
import {
  MediaDuplicateProof
} from '../main/ets/library/importer/MediaDuplicateProof';
import { MediaImportOperation } from '../main/ets/library/importer/MediaImportOperation';

function metadata(): ParsedMetadata {
  return {
    format: MediaFormat.MP3,
    title: '',
    sortTitle: '',
    album: '',
    albumArtists: [],
    artists: [],
    composers: [],
    lyricists: [],
    lyrics: '',
    conductors: [],
    performers: [],
    genres: [],
    trackNumber: {},
    discNumber: {},
    releaseDate: { precision: 0 },
    originalReleaseDate: { precision: 0 },
    durationMs: 0,
    sampleRate: 0,
    channelCount: 0,
    bitsPerSample: 0,
    bitRate: 0,
    mimeType: '',
    artworks: [],
    rawTags: new Map<string, Array<string>>()
  };
}

function input(uri: string, fingerprint: string): TrackImportInput {
  return {
    uri: uri,
    displayName: uri,
    fileSize: 1,
    modifiedAt: 1,
    quickFingerprint: 'quick',
    fullFingerprint: fingerprint,
    authorizationPersisted: true,
    metadata: metadata()
  };
}

function proof(operation: MediaImportOperation,
  lookup: (fileSize: number, quick: string) => Promise<Array<DuplicateCandidate>>,
  calculate: (uri: string) => Promise<string>): MediaDuplicateProof {
  return new MediaDuplicateProof(
    operation,
    lookup,
    calculate,
    async (_trackId: number, _fingerprint: string): Promise<void> => {
    }
  );
}

export default function mediaDuplicateProofTest() {
  describe('Media duplicate proof', () => {
    it('deduplicates candidate lookup promises', 0, async () => {
      const operation = new MediaImportOperation();
      let calls = 0;
      let resolveLookup: ((value: Array<DuplicateCandidate>) => void) | undefined;
      const service = proof(operation,
        (_fileSize: number, _quick: string): Promise<Array<DuplicateCandidate>> => {
          calls += 1;
          return new Promise<Array<DuplicateCandidate>>(
            (resolve: (value: Array<DuplicateCandidate>) => void): void => {
              resolveLookup = resolve;
            }
          );
        },
        async (_uri: string): Promise<string> => 'full'
      );
      const first = service.findCandidates(1, 'quick');
      const second = service.findCandidates(1, 'quick');
      resolveLookup?.([]);
      await Promise.all([first, second]);
      expect(calls).assertEqual(1);
    });

    it('evicts a rejected candidate lookup by promise identity', 0, async () => {
      const operation = new MediaImportOperation();
      let calls = 0;
      const service = proof(operation,
        async (_fileSize: number, _quick: string): Promise<Array<DuplicateCandidate>> => {
          calls += 1;
          if (calls === 1) {
            throw new Error('first failure');
          }
          return [];
        },
        async (_uri: string): Promise<string> => 'full'
      );
      try {
        await service.findCandidates(1, 'quick');
      } catch (_error) {
      }
      await service.findCandidates(1, 'quick');
      expect(calls).assertEqual(2);
    });

    it('computes full proofs only for colliding batch groups and partitions them', 0, async () => {
      const operation = new MediaImportOperation();
      let hashes = 0;
      const service = proof(
        operation,
        async (_fileSize: number, _quick: string): Promise<Array<DuplicateCandidate>> => [],
        async (uri: string): Promise<string> => {
          hashes += 1;
          return uri === 'a' || uri === 'b' ? 'same' : 'other';
        }
      );
      const inputs = [input('a', ''), input('b', ''), input('single', '')];
      inputs[2].quickFingerprint = 'single';
      await service.ensureBatchProofs(inputs);
      const result = service.partitionBatchDuplicates(inputs);
      expect(hashes).assertEqual(2);
      expect(result.unique.length).assertEqual(2);
      expect(result.duplicates.length).assertEqual(1);
      expect(result.duplicates[0].source.uri).assertEqual('a');
      expect(result.duplicates[0].duplicate.uri).assertEqual('b');
    });

    it('stops after proof when the shared operation is cancelled', 0, async () => {
      const operation = new MediaImportOperation();
      const service = proof(
        operation,
        async (_fileSize: number, _quick: string): Promise<Array<DuplicateCandidate>> => [],
        async (_uri: string): Promise<string> => {
          operation.cancel();
          return 'full';
        }
      );
      let cancelled = false;
      try {
        await service.ensureBatchProofs([input('a', ''), input('b', '')]);
      } catch (_error) {
        cancelled = true;
      }
      expect(cancelled).assertTrue();
    });
  });
}
