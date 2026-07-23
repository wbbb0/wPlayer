import { PlayerFrame, PlayerLayoutSpec } from './PlayerMotion';

@Observed
export class MiniPlayerBinding {
  expanded: boolean = false;
  offsetX: number = 0;
  sourceVisible: boolean = true;
  sourceMarqueeActive: boolean = true;
  measuredFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
}
