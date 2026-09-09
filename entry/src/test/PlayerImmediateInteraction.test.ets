import { describe, expect, it } from '@ohos/hypium';
import { LyricsWindowCache } from '../main/ets/playback/lyrics/LyricsWindowCache';
import { PlayerArtworkTapSequence } from '../main/ets/components/player/PlayerArtworkTapSequence';

export default function playerImmediateInteractionTest() {
  describe('Immediate player interaction', () => {
    it('makes prefetched lyrics and confirmed empty lyrics available synchronously', 0, async () => {
      const cache = new LyricsWindowCache();
      cache.setWindow([1, 2, 3]);
      await cache.prefetch(async (id: number): Promise<string> => id === 2 ? '' : '[00:01]line');
      expect(cache.get(1)?.lines[0].text).assertEqual('line');
      expect(cache.get(2)?.source).assertEqual('');
      cache.setWindow([2, 3, 4]);
      expect(cache.get(2)?.source).assertEqual('');
      expect(cache.get(1)).assertUndefined();
      expect(cache.get(4)).assertUndefined();
    });

    it('shares in-flight work with selection and ignores late completion after reset', 0, async () => {
      const cache = new LyricsWindowCache();
      cache.setWindow([1]);
      let finish: (source: string) => void = (_source: string): void => {};
      const source = new Promise<string>((resolve) => { finish = resolve; });
      let reads = 0;
      const read = (): Promise<string> => { reads += 1; return source; };
      const first = cache.load(1, read);
      const selected = cache.load(1, read);
      expect(reads).assertEqual(1);
      cache.reset();
      cache.setWindow([1]);
      finish('[00:01]old');
      await first;
      await selected;
      expect(cache.get(1)).assertUndefined();
      await cache.load(1, async (): Promise<string> => '[00:02]new');
      expect(cache.get(1)?.lines[0].text).assertEqual('new');
    });

    it('does not turn a read failure into cached absence', 0, async () => {
      const cache = new LyricsWindowCache();
      cache.setWindow([1]);
      await cache.prefetch(async (_id: number): Promise<string> => { throw new Error('read failed'); });
      expect(cache.get(1)).assertUndefined();
      await cache.load(1, async (): Promise<string> => 'recovered');
      expect(cache.get(1)?.source).assertEqual('recovered');
    });

    it('rejects horizontal vertical and returning drags while allowing small tap jitter', 0, () => {
      const touch = new PlayerArtworkTapSequence();
      touch.begin(100, 100);
      touch.move(103, 104);
      expect(touch.allowsTap()).assertTrue();
      touch.move(120, 100);
      touch.move(100, 100);
      expect(touch.allowsTap()).assertFalse();
      touch.begin(100, 100);
      touch.move(100, 120);
      expect(touch.allowsTap()).assertFalse();
      touch.begin(100, 100);
      touch.cancel();
      expect(touch.allowsTap()).assertFalse();
      touch.begin(100, 100);
      expect(touch.allowsTap()).assertTrue();
    });
  });
}
