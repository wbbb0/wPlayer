import { PlayerFrame, PlayerLayoutSpec } from './PlayerMotion';

@Observed
export class MiniPlayerBinding {
  expanded: boolean = false;
  offsetX: number = 0;
  sourceVisible: boolean = true;
  sourceMarqueeActive: boolean = true;
  albumChromeInstanceId: number = -1;
  albumChromeBackgroundColor: string = '';
  measuredFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };

  hasAlbumChrome(): boolean {
    return this.albumChromeInstanceId >= 0 &&
      this.albumChromeBackgroundColor.length > 0;
  }

  applyAlbumChrome(instanceId: number, backgroundColor: string): void {
    this.albumChromeInstanceId = instanceId;
    this.albumChromeBackgroundColor = backgroundColor;
  }

  clearAlbumChrome(instanceId: number): void {
    if (this.albumChromeInstanceId !== instanceId) {
      return;
    }
    this.albumChromeInstanceId = -1;
    this.albumChromeBackgroundColor = '';
  }
}
