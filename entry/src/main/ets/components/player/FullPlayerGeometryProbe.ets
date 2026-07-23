import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { FullPlayerContent } from './FullPlayerContent';
import { LibraryStore } from '../../library/store/LibraryStore';
import {
  FullPlayerPage,
  PlayerFrame,
  PlayerPoint
} from './PlayerMotion';

@Component
export struct PlayerGeometryProbe {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @ObjectLink libraryStore: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop paneCount: number = 1;
  @Prop primaryContentColor: string = '';
  @Prop previousArtworkTarget: PlayerPoint = { x: 0, y: 0 };
  @Prop previousCenteredArtworkTarget: PlayerPoint = { x: 0, y: 0 };
  onArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  onCenteredArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};
  onPlaybackButtonTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};

  build() {
    Stack() {
      FullPlayerContent({
        playerStore: this.playerStore,
        libraryStore: this.libraryStore,
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
        },
        onPlaybackButtonTarget: (target: PlayerFrame): void => {
          this.onPlaybackButtonTarget(target);
        }
      })
    }
    .width('100%')
    .height('100%')
    .opacity(0)
    .hitTestBehavior(HitTestMode.None)
  }
}
