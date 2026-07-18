import { describe, expect, it } from '@ohos/hypium';
import { PlaybackTransportState, PlayerState } from '../main/ets/playback/model/PlaybackModels';
import { PlaybackStateReducer } from '../main/ets/playback/support/PlaybackStateReducer';

export default function playbackStateReducerTest() {
  describe('Playback state projection', () => {
    it('keeps playing throughout a continuous source replacement', 0, () => {
      const reducer = new PlaybackStateReducer();
      reducer.beginSourceChange(true);
      reducer.reduce(PlayerState.PLAYING, true);

      expect(reducer.beginSourceChange(true)).assertEqual(PlaybackTransportState.PLAYING);
      expect(reducer.reduce(PlayerState.IDLE, true)).assertEqual(PlaybackTransportState.PLAYING);
      expect(reducer.reduce(PlayerState.LOADING, true)).assertEqual(PlaybackTransportState.PLAYING);
      expect(reducer.reduce(PlayerState.READY, true)).assertEqual(PlaybackTransportState.PLAYING);
      expect(reducer.reduce(PlayerState.PLAYING, true)).assertEqual(PlaybackTransportState.PLAYING);
    });

    it('publishes preparing only when playback starts from a non-playing state', 0, () => {
      const reducer = new PlaybackStateReducer();
      expect(reducer.beginSourceChange(true)).assertEqual(PlaybackTransportState.PREPARING);
      expect(reducer.reduce(PlayerState.READY, true)).assertEqual(PlaybackTransportState.PREPARING);
      expect(reducer.reduce(PlayerState.PLAYING, true)).assertEqual(PlaybackTransportState.PLAYING);
    });

    it('honors pause while a source is still loading', 0, () => {
      const reducer = new PlaybackStateReducer();
      reducer.beginSourceChange(true);
      expect(reducer.updateIntent(false)).assertEqual(PlaybackTransportState.PAUSED);
      expect(reducer.reduce(PlayerState.READY, false)).assertEqual(PlaybackTransportState.PAUSED);
      expect(reducer.reduce(PlayerState.PLAYING, false)).assertEqual(PlaybackTransportState.PAUSED);
    });

    it('defers completed until queue continuation has been decided', 0, () => {
      const reducer = new PlaybackStateReducer();
      reducer.beginSourceChange(true);
      reducer.reduce(PlayerState.PLAYING, true);
      expect(reducer.reduce(PlayerState.COMPLETED, true)).assertEqual(PlaybackTransportState.PLAYING);
      expect(reducer.settleCompletion()).assertEqual(PlaybackTransportState.COMPLETED);
    });
  });
}
