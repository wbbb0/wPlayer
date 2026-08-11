import { PlayerFrame, PlayerLayoutSpec } from './PlayerMotion';
import { QueueEntry } from '../../playback/model/PlaybackModels';

@Observed
export class MiniPlayerBinding {
  expanded: boolean = false;
  offsetX: number = 0;
  trackPagerActive: boolean = false;
  trackPagerViewportWidth: number = 0;
  trackPagerPrevious?: QueueEntry;
  trackPagerCurrent?: QueueEntry;
  trackPagerNext?: QueueEntry;
  sourceVisible: boolean = true;
  sourceMarqueeActive: boolean = true;
  measuredFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
}

@Observed
export class PlayerDynamicBackgroundBinding {
  active: boolean = false;
}
