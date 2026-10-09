import { describe, expect, it } from '@ohos/hypium';
import { PlaybackStopOperation } from '../main/ets/playback/coordinator/PlaybackStopOperation';

export default function playbackStopOperationTest() {
  describe('Playback transition stop ownership', () => {
    it('reports current cleanup failure and prevents the transition commit', 0, async () => {
      let state = 'playing';
      let committed = false;
      let rejected = false;
      await PlaybackStopOperation.run(async (): Promise<void> => { throw new Error('reset failed'); },
        (): boolean => true, (): void => { committed = true; },
        (_error: Object): void => { state = 'error'; }).catch((): void => { rejected = true; });
      expect(rejected).assertTrue();
      expect(committed).assertFalse();
      expect(state).assertEqual('error');
    });

    it('does not publish failure into a newer source but still rejects the obsolete transition', 0, async () => {
      let current = true;
      let state = 'loading';
      let committed = false;
      let fail: (error: Error) => void = (_error: Error): void => {};
      const stop = new Promise<void>((_resolve, reject): void => { fail = reject; });
      let rejected = false;
      const pending = PlaybackStopOperation.run((): Promise<void> => stop,
        (): boolean => current, (): void => { committed = true; },
        (_error: Object): void => { state = 'error'; }).catch((): void => { rejected = true; });
      current = false;
      fail(new Error('old stop failed'));
      await pending;
      expect(rejected).assertTrue();
      expect(committed).assertFalse();
      expect(state).assertEqual('loading');
    });

    it('never clears a newer source after an obsolete stop resolves', 0, async () => {
      let current = true;
      let commits = 0;
      let failures = 0;
      let finish: () => void = (): void => {};
      const stop = new Promise<void>((resolve): void => { finish = resolve; });
      let rejected = false;
      const pending = PlaybackStopOperation.run((): Promise<void> => stop,
        (): boolean => current, (): void => { commits += 1; },
        (_error: Object): void => { failures += 1; }).catch((): void => { rejected = true; });
      current = false;
      finish();
      await pending;
      expect(rejected).assertTrue();
      expect(commits).assertEqual(0);
      expect(failures).assertEqual(0);
      await PlaybackStopOperation.run(async (): Promise<void> => {}, (): boolean => true,
        (): void => { commits += 1; }, (_error: Object): void => { failures += 1; });
      expect(commits).assertEqual(1);
      expect(failures).assertEqual(0);
    });
  });
}
