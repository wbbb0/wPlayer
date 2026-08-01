import { curves } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { BundledArtworkCatalog } from '../../library/artwork/BundledArtworkCatalog';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { ContextPreviewGeometry } from '../library/ContextPreviewGeometry';
import { LibraryContextInteraction } from '../library/LibraryContextInteraction';
import {
  CurrentTrackActionMenu,
  CurrentTrackActionMenuParams
} from './PlayerActionMenus';
import {
  PlayerFrame,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec
} from './PlayerMotion';

@Component
export struct PlayerMorphArtwork {
  @ObjectLink @Watch('onPlayerStoreChanged') playerStore: PlayerStore;
  @State contextMenuShown: boolean = false;
  @State playbackVisualProgress: number = 1;
  private contextPreviewWidth: number = 0;
  private contextPreviewHeight: number = 0;
  private contextPreviewRestScale: number = 1;
  private playbackVisualTarget: number = 1;
  private mounted: boolean = false;
  @Prop geometryProgress: number = 0;
  @Prop positionProgress: number = 0;
  @Prop elementOpacity: number = 1;
  @Prop morphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop frozenMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  @Prop fullPlayerFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop fullPlayerArtworkTarget: PlayerFrame = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y,
    width: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
    height: PlayerLayoutSpec.FULL_ARTWORK_SIZE
  };
  @Prop sourceWidth: number = 0;
  @Prop sourceHeight: number = 0;
  sourceProvider: () => image.PixelMap | ResourceStr =
    (): ResourceStr => BundledArtworkCatalog.resolve(BundledArtworkCatalog.DEFAULT_FULL);
  onInsertNext: () => void = (): void => {};
  onAppendToQueue: () => void = (): void => {};
  onAddToPlaylist: () => void = (): void => {};
  onOpenDetails: () => void = (): void => {};
  onShareTrackFile: () => void = (): void => {};
  onCompletedCollectionChange: (enabled: boolean) => void =
    (_enabled: boolean): void => {};

  aboutToAppear(): void {
    this.mounted = true;
    this.playbackVisualTarget = this.currentPlaybackVisualTarget();
    this.playbackVisualProgress = this.playbackVisualTarget;
  }

  aboutToDisappear(): void {
    this.mounted = false;
  }

  private currentPlaybackVisualTarget(): number {
    return PlayerMotionSpec.artworkPlaybackVisualTarget(
      this.playerStore.keepsActivePlaybackVisual()
    );
  }

  private onPlayerStoreChanged(): void {
    const target = this.currentPlaybackVisualTarget();
    if (target === this.playbackVisualTarget) {
      return;
    }
    this.playbackVisualTarget = target;
    if (!this.mounted || this.morphPhase !== PlayerMorphPhase.OPEN) {
      this.playbackVisualProgress = target;
      return;
    }
    this.getUIContext().animateTo({
      curve: curves.springMotion(
        PlayerMotionSpec.ARTWORK_STATE_SPRING_RESPONSE,
        PlayerMotionSpec.ARTWORK_STATE_SPRING_DAMPING
      )
    }, () => {
      this.playbackVisualProgress = target;
    });
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private morphValue(start: number, end: number): number {
    const progress = this.clamp(this.geometryProgress, 0, 1);
    return start + (end - start) * progress;
  }

  private morphPositionValue(start: number, end: number): number {
    const progress = this.clamp(this.positionProgress, 0, 1);
    return start + (end - start) * progress;
  }

  private source(): image.PixelMap | ResourceStr {
    return this.sourceProvider();
  }

  private targetArtworkWidth(): number {
    return this.fullPlayerArtworkTarget.width;
  }

  private targetArtworkHeight(): number {
    return this.fullPlayerArtworkTarget.height;
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
    const fullPlayerScale = PlayerMotionSpec.artworkPlaybackVisualValue(
      PlayerMotionSpec.PAUSED_ARTWORK_SCALE,
      1,
      this.playbackVisualProgress
    );
    return 1 - (1 - fullPlayerScale) * this.clamp(this.geometryProgress, 0, 1);
  }

  private playbackRestScale(): number {
    return PlayerMotionSpec.artworkPlaybackVisualValue(
      PlayerMotionSpec.PAUSED_ARTWORK_SCALE,
      1,
      this.playbackVisualProgress
    );
  }

  private playbackShadowRadius(): number {
    return PlayerMotionSpec.artworkPlaybackVisualValue(
      PlayerMotionSpec.PAUSED_ARTWORK_SHADOW_RADIUS,
      PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS,
      this.playbackVisualProgress
    ) * this.clamp(this.geometryProgress, 0, 1);
  }

  private playbackShadowOffsetY(): number {
    return PlayerMotionSpec.artworkPlaybackVisualValue(
      PlayerMotionSpec.PAUSED_ARTWORK_SHADOW_OFFSET_Y,
      PlayerMotionSpec.FULL_ARTWORK_SHADOW_OFFSET_Y,
      this.playbackVisualProgress
    ) * this.clamp(this.geometryProgress, 0, 1);
  }

  private artworkX(): number {
    return this.morphPositionValue(
      this.frozenMiniPlayerFrame.x + PlayerLayoutSpec.MINI_ARTWORK_INSET,
      this.fullPlayerArtworkTarget.x
    );
  }

  private artworkY(): number {
    return this.morphPositionValue(
      this.frozenMiniPlayerFrame.y + PlayerLayoutSpec.MINI_ARTWORK_INSET,
      this.fullPlayerArtworkTarget.y
    );
  }

  private artworkOpacity(): number {
    return this.clamp(this.elementOpacity, 0, 1);
  }

  private showContextMenu(event: GestureEvent): void {
    const frame = ContextPreviewGeometry.fromGesture(event);
    if (frame.width <= 0 || frame.height <= 0) {
      console.warn('Unable to measure player artwork context preview');
      return;
    }
    this.contextPreviewWidth = frame.width;
    this.contextPreviewHeight = frame.height;
    this.contextPreviewRestScale = this.playbackRestScale();
    LibraryContextInteraction.triggerHaptic('Player artwork');
    this.contextMenuShown = true;
  }

  @Builder
  private CurrentTrackMenu() {
    CurrentTrackActionMenu(new CurrentTrackActionMenuParams({
      trackAvailable: this.playerStore.currentTrack !== undefined,
      completedCollectionEnabled: this.playerStore.completedCollectionEnabled,
      onInsertNext: this.onInsertNext,
      onAppendToQueue: this.onAppendToQueue,
      onAddToPlaylist: this.onAddToPlaylist,
      onOpenDetails: this.onOpenDetails,
      onShareFile: this.onShareTrackFile,
      onCompletedCollectionChange: this.onCompletedCollectionChange
    }))
  }

  @Builder
  private ContextMenuPreview() {
    Stack() {
      ArtworkView({
        sourceProvider: (): image.PixelMap | ResourceStr => this.source(),
        sourceRevision: this.playerStore.heroArtworkRevision,
        sourceWidth: this.sourceWidth,
        sourceHeight: this.sourceHeight,
        slotWidth: this.contextPreviewWidth * this.contextPreviewRestScale,
        slotAspectRatio: this.contextPreviewHeight > 0 ?
          this.contextPreviewWidth / this.contextPreviewHeight : 1,
        fitMode: ArtworkFitMode.COVER,
        resolvedCornerRadius: this.sourceRadius() * this.contextPreviewRestScale,
        shadowEnabled: false,
        interpolation: ImageInterpolation.Medium
      })
    }
    .width(this.contextPreviewWidth * this.contextPreviewRestScale)
    .height(this.contextPreviewHeight * this.contextPreviewRestScale)
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
        shadowRadius: this.playbackShadowRadius(),
        shadowOffsetY: this.playbackShadowOffsetY(),
        interpolation: ImageInterpolation.Medium
      })
        .scale({
          x: this.playbackScale(),
          y: this.playbackScale()
        })
    }
    .width(this.artworkWidth())
    .height(this.artworkHeight())
    .renderFit(RenderFit.RESIZE_FILL)
    .opacity(this.contextMenuShown ? 0 : this.artworkOpacity())
    .position({ x: 0, y: 0 })
    .translate({ x: this.artworkX(), y: this.artworkY() })
    .accessibilityText('歌曲封面，长按打开更多操作')
    .bindContextMenu(
      this.contextMenuShown,
      this.CurrentTrackMenu(),
      {
        placement: Placement.BottomRight,
        preview: this.ContextMenuPreview,
        previewBorderRadius: 0,
        layoutRegionMargin: ContextPreviewGeometry.layoutRegionMargin(),
        previewAnimationOptions: {
          scale: [
            1,
            PlayerMotionSpec.artworkContextPreviewAnimationEndScale(
              this.contextPreviewRestScale
            )
          ]
        },
        previewScaleMode: PreviewScaleMode.CONSTANT,
        onDisappear: (): void => {
          this.contextMenuShown = false;
        }
      }
    )
    .gesture(
      LongPressGesture({
        repeat: false,
        duration: LibraryContextInteraction.LONG_PRESS_DURATION
      }).onAction((event: GestureEvent): void => this.showContextMenu(event))
    )
  }
}
