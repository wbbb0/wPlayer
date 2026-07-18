import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { FullPlayerContent } from './FullPlayerContent';
import { PlayerMarqueeMotionStore } from './PlayerTrackMarquee';
import {
  FullPlayerPage,
  PlayerFrame,
  PlayerPoint
} from './PlayerMotion';

@Component
export struct PlayerGeometryProbe {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink marqueeMotionStore: PlayerMarqueeMotionStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop paneCount: number = 1;
  @Prop primaryContentColor: string = '';
  @Prop previousArtworkTarget: PlayerPoint = { x: 0, y: 0 };
  @Prop previousCenteredArtworkTarget: PlayerPoint = { x: 0, y: 0 };
  onArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  onCenteredArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};

  build() {
    Stack() {
      FullPlayerContent({
        playerStore: this.playerStore,
        marqueeMotionStore: this.marqueeMotionStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        showArtwork: false,
        heroArtworkInterpolation: this.settingsStore.highQualityHeroArtwork ?
          ImageInterpolation.High : ImageInterpolation.Medium,
        measuresArtworkTarget: true,
        rootFrame: this.rootFrame,
        pagePosition: FullPlayerPage.COVER,
        paneCount: this.paneCount,
        primaryContentColor: this.primaryContentColor,
        previousArtworkTarget: this.previousArtworkTarget,
        previousCenteredArtworkTarget: this.previousCenteredArtworkTarget,
        onClose: (): void => {},
        onArtworkTarget: (target: PlayerPoint): void => {
          this.onArtworkTarget(target);
        },
        onCenteredArtworkTarget: (target: PlayerPoint): void => {
          this.onCenteredArtworkTarget(target);
        }
      })
    }
    .width('100%')
    .height('100%')
    .opacity(0)
    .hitTestBehavior(HitTestMode.None)
  }
}
