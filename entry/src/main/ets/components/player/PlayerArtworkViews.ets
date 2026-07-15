import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { ArtworkLayout } from '../artwork/ArtworkLayout';
import { PlayerLayoutSpec, PlayerMotionSpec } from './PlayerMotion';
import { PlayerStore } from '../../playback/model/PlaybackModels';

@Component
export struct PlayerMiniArtwork {
  @ObjectLink playerStore: PlayerStore;

  build() {
    ArtworkView({
      sourcePixelMap: this.playerStore.miniArtwork,
      sourcePath: this.playerStore.miniArtworkUri,
      slotWidth: PlayerLayoutSpec.MINI_ARTWORK_SIZE,
      fitMode: ArtworkFitMode.COVER,
      cornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
      circularProgress: 1,
      shadowEnabled: false,
      shadowRadius: 0,
      shadowOffsetY: 0
    })
  }
}

@Component
export struct PlayerHeroArtwork {
  @ObjectLink playerStore: PlayerStore;
  @Prop slotSize: number = PlayerLayoutSpec.FULL_ARTWORK_SIZE;
  @Prop cornerRadius: number = PlayerLayoutSpec.FULL_ARTWORK_RADIUS;

  private artworkWidth(): number {
    return ArtworkLayout.containedSize(
      this.playerStore.currentTrack?.artworkWidth ?? 0,
      this.playerStore.currentTrack?.artworkHeight ?? 0,
      this.slotSize,
      this.slotSize
    ).width;
  }

  private artworkHeight(): number {
    return ArtworkLayout.containedSize(
      this.playerStore.currentTrack?.artworkWidth ?? 0,
      this.playerStore.currentTrack?.artworkHeight ?? 0,
      this.slotSize,
      this.slotSize
    ).height;
  }

  build() {
    Stack() {
      Stack() {
        if (this.playerStore.heroArtworkPreferPixelMap && this.playerStore.heroArtwork !== undefined) {
          Image(this.playerStore.heroArtwork)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else if (this.playerStore.heroArtworkUri.length > 0) {
          Image(this.playerStore.heroArtworkUri)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Image($r('app.media.default_album_cover'))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        }
      }
      .width(this.artworkWidth())
      .height(this.artworkHeight())
      .borderRadius(Math.min(this.cornerRadius, Math.min(this.artworkWidth(), this.artworkHeight()) / 2))
      .clip(true)
      .shadow({
        radius: PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS,
        color: $r('app.color.artwork_shadow'),
        offsetY: PlayerMotionSpec.FULL_ARTWORK_SHADOW_OFFSET_Y
      })
    }
    .width(this.slotSize)
    .height(this.slotSize)
  }
}
