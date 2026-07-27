import { PlayerStore } from '../../playback/model/PlaybackModels';
import { FullPlayerContent } from './FullPlayerContent';
import { LibraryStore } from '../../library/store/LibraryStore';
import {
  FullPlayerPage,
  PlayerFrame
} from './PlayerMotion';

@Component
export struct PlayerGeometryProbe {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink libraryStore: LibraryStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop paneCount: number = 1;
  @Prop primaryContentColor: string = '';
  @Prop artworkSourceWidth: number = 0;
  @Prop artworkSourceHeight: number = 0;
  @Prop previousArtworkFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop previousCenteredArtworkFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  onArtworkTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};
  onCenteredArtworkTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};
  onPlaybackButtonTarget: (target: PlayerFrame) => void = (_target: PlayerFrame): void => {};

  build() {
    Stack() {
      FullPlayerContent({
        playerStore: this.playerStore,
        libraryStore: this.libraryStore,
        topInset: this.topInset,
        bottomInset: this.bottomInset,
        showArtwork: false,
        measuresArtworkTarget: true,
        rootFrame: this.rootFrame,
        pagePosition: FullPlayerPage.COVER,
        paneCount: this.paneCount,
        primaryContentColor: this.primaryContentColor,
        artworkSourceWidth: this.artworkSourceWidth,
        artworkSourceHeight: this.artworkSourceHeight,
        previousArtworkFrame: this.previousArtworkFrame,
        previousCenteredArtworkFrame: this.previousCenteredArtworkFrame,
        onClose: (): void => {},
        onArtworkTarget: (target: PlayerFrame): void => {
          this.onArtworkTarget(target);
        },
        onCenteredArtworkTarget: (target: PlayerFrame): void => {
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
