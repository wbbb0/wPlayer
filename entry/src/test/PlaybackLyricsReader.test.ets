import { describe, expect, it } from '@ohos/hypium';
import { PlaybackLyricsReader } from '../main/ets/playback/lyrics/PlaybackLyricsReader';
import { LyricsWindowCache } from '../main/ets/playback/lyrics/LyricsWindowCache';
import { PlaybackTrack } from '../main/ets/playback/model/PlaybackModels';
import { AvailabilityState, MediaFormat } from '../main/ets/library/model/LibraryModels';

function lyricTrack(): PlaybackTrack {
  return {
    id: 1, uri: 'file://opaque-picker-uri', title: 'test', artistDisplay: '', albumDisplay: '',
    durationMs: 1000, fileSize: 20, modifiedAt: 1, format: MediaFormat.MP3,
    availability: AvailabilityState.AVAILABLE, authorizationPersisted: true,
    smallArtworkHash: '', smallArtworkPath: '', largeArtworkHash: '', largeArtworkPath: '',
    artworkWidth: 0, artworkHeight: 0, palettePrimary: '', paletteSecondary: '', paletteAccent: ''
  };
}

export default function playbackLyricsReaderTest() {
  describe('Authorized lyric reads', () => {
    it('shares authorized prefetch with selection before touching the source', 0, async () => {
      let active = false;
      let reads = 0;
      let grants = 0;
      let activate: (value: boolean) => void = (_value: boolean): void => {};
      const permission = new Promise<boolean>((resolve): void => { activate = resolve; });
      const reader = new PlaybackLyricsReader(async (_uri: string): Promise<boolean> => {
        grants += 1;
        active = await permission;
        return active;
      }, async (_track: PlaybackTrack): Promise<string> => {
        expect(active).assertTrue();
        reads += 1;
        return '[00:01]authorized';
      });
      const track = lyricTrack();
      const cache = new LyricsWindowCache();
      cache.setWindow([track.id]);
      const prefetch = cache.prefetch((_id: number): Promise<string> => reader.read(track));
      const selected = cache.load(track.id, (): Promise<string> => reader.read(track));
      expect(reads).assertEqual(0);
      activate(true);
      await prefetch;
      expect((await selected).source).assertEqual('[00:01]authorized');
      expect(reads).assertEqual(1);
      expect(grants).assertEqual(1);
    });

    it('does not cache revoked access as missing lyrics and can recover', 0, async () => {
      let granted = false;
      let reads = 0;
      const reader = new PlaybackLyricsReader(async (_uri: string): Promise<boolean> => granted,
        async (_track: PlaybackTrack): Promise<string> => { reads += 1; return 'recovered'; });
      const track = lyricTrack();
      const cache = new LyricsWindowCache();
      cache.setWindow([track.id]);
      await cache.prefetch((_id: number): Promise<string> => reader.read(track));
      expect(reads).assertEqual(0);
      expect(cache.get(track.id)).assertUndefined();
      granted = true;
      const result = await cache.load(track.id, (): Promise<string> => reader.read(track));
      expect(result.source).assertEqual('recovered');
      expect(reads).assertEqual(1);
    });
  });
}
