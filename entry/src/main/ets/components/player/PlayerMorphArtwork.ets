import { curves } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { ArtworkLayout } from '../artwork/ArtworkLayout';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import {
  FullPlayerPage,
  FullPlayerPagerSpec,
  PlayerFrame,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec,
  PlayerPoint
} from './PlayerMotion';

@Component
export struct PlayerMorphArtwork {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop expandProgress: number = 0;
  @Prop morphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  @Prop fullPlayerPage: FullPlayerPage = FullPlayerPage.COVER;
  @Prop fullPlayerPagePosition: number = FullPlayerPage.COVER;
  @Prop renderedPaneCount: number = 1;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop frozenMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  @Prop fullPlayerFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop fullPlayerArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  @Prop sourceWidth: number = 0;
  @Prop sourceHeight: number = 0;
  sourceProvider: () => image.PixelMap | ResourceStr =
    (): ResourceStr => $r('app.media.default_album_cover');

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private morphValue(start: number, end: number): number {
    const progress = this.clamp(this.expandProgress, 0, 1);
    return start + (end - start) * progress;
  }

  private source(): image.PixelMap | ResourceStr {
    return this.sourceProvider();
  }

  private fullArtworkSlotSize(): number {
    return PlayerLayoutSpec.fullArtworkSize(
      FullPlayerPagerSpec.pageSpan(this.fullPlayerFrame.width,
        FullPlayerPagerSpec.paneCount(this.fullPlayerFrame.width, this.fullPlayerFrame.height)),
      this.fullPlayerFrame.height,
      this.topInset,
      this.bottomInset
    );
  }

  private targetArtworkWidth(): number {
    const slotSize = this.fullArtworkSlotSize();
    return ArtworkLayout.containedSize(
      this.sourceWidth,
      this.sourceHeight,
      slotSize,
      slotSize
    ).width;
  }

  private targetArtworkHeight(): number {
    const slotSize = this.fullArtworkSlotSize();
    return ArtworkLayout.containedSize(
      this.sourceWidth,
      this.sourceHeight,
      slotSize,
      slotSize
    ).height;
  }

  private artworkWidth(): number {
    return this.morphValue(PlayerLayoutSpec.MINI_ARTWORK_SIZE, this.targetArtworkWidth());
  }

  private artworkHeight(): number {
    return this.morphValue(PlayerLayoutSpec.MINI_ARTWORK_SIZE, this.targetArtworkHeight());
  }

  private artworkAspectRatio(): number {
    const height = this.artworkHeight();
    return height > 0 ? this.artworkWidth() / height : 1;
  }

  private sourceRadius(): number {
    const fullRadius = Math.min(
      PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
      Math.min(this.targetArtworkWidth(), this.targetArtworkHeight()) / 2
    );
    return this.morphValue(PlayerLayoutSpec.MINI_ARTWORK_RADIUS, fullRadius);
  }

  private playbackScale(): number {
    const fullPlayerScale = this.playerStore.keepsActivePlaybackVisual() ?
      1 : PlayerMotionSpec.PAUSED_ARTWORK_SCALE;
    return 1 - (1 - fullPlayerScale) * this.clamp(this.expandProgress, 0, 1);
  }

  private artworkX(): number {
    return this.morphValue(
      this.frozenMiniPlayerFrame.x + PlayerLayoutSpec.MINI_ARTWORK_INSET,
      this.fullPlayerArtworkTarget.x + (this.fullArtworkSlotSize() - this.targetArtworkWidth()) / 2
    );
  }

  private artworkY(): number {
    return this.morphValue(
      this.frozenMiniPlayerFrame.y + PlayerLayoutSpec.MINI_ARTWORK_INSET,
      this.fullPlayerArtworkTarget.y + (this.fullArtworkSlotSize() - this.targetArtworkHeight()) / 2
    );
  }

  private artworkOpacity(): number {
    if (this.renderedPaneCount > 1) {
      return 1;
    }
    if (this.morphPhase === PlayerMorphPhase.OPEN) {
      return this.clamp(1 - Math.abs(this.fullPlayerPagePosition - FullPlayerPage.COVER), 0, 1);
    }
    if (this.fullPlayerPage === FullPlayerPage.COVER) {
      return 1;
    }
    return FullPlayerPagerSpec.sidePageArtworkOpacity(this.expandProgress);
  }

  build() {
    Stack() {
      ArtworkView({
        sourceProvider: (): image.PixelMap | ResourceStr => this.source(),
        sourceRevision: this.playerStore.heroArtworkRevision,
        sourceWidth: this.sourceWidth,
        sourceHeight: this.sourceHeight,
        slotWidth: this.artworkWidth(),
        slotAspectRatio: this.artworkAspectRatio(),
        fitMode: ArtworkFitMode.COVER,
        resolvedCornerRadius: this.sourceRadius(),
        shadowEnabled: true,
        shadowRadius: (this.playerStore.keepsActivePlaybackVisual() ?
          PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS :
          PlayerMotionSpec.PAUSED_ARTWORK_SHADOW_RADIUS) *
            this.clamp(this.expandProgress, 0, 1),
        shadowOffsetY: (this.playerStore.keepsActivePlaybackVisual() ?
          PlayerMotionSpec.FULL_ARTWORK_SHADOW_OFFSET_Y :
          PlayerMotionSpec.PAUSED_ARTWORK_SHADOW_OFFSET_Y) *
            this.clamp(this.expandProgress, 0, 1),
        animateShadowChanges: this.morphPhase === PlayerMorphPhase.OPEN,
        shadowSpringResponse: PlayerMotionSpec.ARTWORK_STATE_SPRING_RESPONSE,
        shadowSpringDamping: PlayerMotionSpec.ARTWORK_STATE_SPRING_DAMPING,
        interpolation: this.settingsStore.highQualityHeroArtwork ?
          ImageInterpolation.High : ImageInterpolation.Medium
      })
        .scale({
          x: this.playbackScale(),
          y: this.playbackScale()
        })
        .animation(this.morphPhase === PlayerMorphPhase.OPEN ? {
          curve: curves.springMotion(
            PlayerMotionSpec.ARTWORK_STATE_SPRING_RESPONSE,
            PlayerMotionSpec.ARTWORK_STATE_SPRING_DAMPING
          )
        } : { duration: 0 })
    }
    .width(this.artworkWidth())
    .height(this.artworkHeight())
    .opacity(this.artworkOpacity())
    .position({ x: 0, y: 0 })
    .translate({ x: this.artworkX(), y: this.artworkY() })
  }
}
