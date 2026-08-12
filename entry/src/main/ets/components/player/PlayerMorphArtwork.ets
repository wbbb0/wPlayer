import { image } from '@kit.ImageKit';
import { BundledArtworkCatalog } from '../../library/artwork/BundledArtworkCatalog';
import { ArtworkFitMode, ArtworkView } from '../artwork/ArtworkView';
import { ContextPreviewGeometry } from '../library/ContextPreviewGeometry';
import { LibraryContextInteraction } from '../library/LibraryContextInteraction';
import {
  PlayerArtworkVisualBinding
} from './PlayerArtworkPlaybackVisualState';
import {
  CurrentTrackActionMenu,
  CurrentTrackActionMenuParams
} from './PlayerActionMenus';
import {
  PlayerFrame,
  FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID,
  PlayerLayoutSpec,
  PlayerMotionSpec
} from './PlayerMotion';

@Component
export struct PlayerMorphArtwork {
  @ObjectLink playbackVisual: PlayerArtworkVisualBinding;
  @State contextMenuShown: boolean = false;
  private contextPreviewWidth: number = 0;
  private contextPreviewHeight: number = 0;
  private contextPreviewRestScale: number = 1;
  @Prop geometryProgress: number = 0;
  @Prop positionProgress: number = 0;
  @Prop elementOpacity: number = 1;
  @Prop frozenMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  @Prop fullPlayerArtworkTarget: PlayerFrame = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y,
    width: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
    height: PlayerLayoutSpec.FULL_ARTWORK_SIZE
  };
  @Prop sourceWidth: number = 0;
  @Prop sourceHeight: number = 0;
  @Prop artworkSourceRevision: number = 0;
  sourceProvider: () => image.PixelMap | ResourceStr =
    (): ResourceStr => BundledArtworkCatalog.resolve(BundledArtworkCatalog.DEFAULT_FULL);
  onInsertNext: () => void = (): void => {};
  onAppendToQueue: () => void = (): void => {};
  onAddToPlaylist: () => void = (): void => {};
  onOpenDetails: () => void = (): void => {};
  onShareTrackFile: () => void = (): void => {};
  onCompletedCollectionChange: (enabled: boolean) => void =
    (_enabled: boolean): void => {};
  isTrackAvailable: () => boolean = (): boolean => false;
  isCompletedCollectionEnabled: () => boolean = (): boolean => false;
  onTap: () => void = (): void => {};
  onArtworkReady: (actorGeneration: number) => void = (_actorGeneration: number): void => {};
  onArtworkError: (actorGeneration: number) => void = (_actorGeneration: number): void => {};
  @Prop artworkActorGeneration: number = 0;

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

  private sourceRevision(): number {
    return this.artworkSourceRevision;
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
      this.playbackVisual.progress
    );
    return 1 - (1 - fullPlayerScale) * this.clamp(this.geometryProgress, 0, 1);
  }

  private playbackRestScale(): number {
    return PlayerMotionSpec.artworkPlaybackVisualValue(
      PlayerMotionSpec.PAUSED_ARTWORK_SCALE,
      1,
      this.playbackVisual.progress
    );
  }

  private interactionFrame(): PlayerFrame {
    const scale = this.playbackScale();
    const width = this.artworkWidth() * scale;
    const height = this.artworkHeight() * scale;
    return {
      x: (this.artworkWidth() - width) / 2,
      y: (this.artworkHeight() - height) / 2,
      width: width,
      height: height
    };
  }

  private playbackShadowRadius(): number {
    return PlayerMotionSpec.artworkPlaybackVisualValue(
      PlayerMotionSpec.PAUSED_ARTWORK_SHADOW_RADIUS,
      PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS,
      this.playbackVisual.progress
    ) * this.clamp(this.geometryProgress, 0, 1);
  }

  private playbackShadowOffsetY(): number {
    return PlayerMotionSpec.artworkPlaybackVisualValue(
      PlayerMotionSpec.PAUSED_ARTWORK_SHADOW_OFFSET_Y,
      PlayerMotionSpec.FULL_ARTWORK_SHADOW_OFFSET_Y,
      this.playbackVisual.progress
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

  private blockOuterHorizontalPager(recognizers: Array<GestureRecognizer>): void {
    recognizers.forEach((recognizer: GestureRecognizer): void => {
      if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID) {
        recognizer.preventBegin();
      }
    });
  }

  private requestTap(): void {
    this.onTap();
  }

  @Builder
  private CurrentTrackMenu() {
    CurrentTrackActionMenu(new CurrentTrackActionMenuParams({
      trackAvailable: this.isTrackAvailable(),
      completedCollectionEnabled: this.isCompletedCollectionEnabled(),
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
        sourceRevision: this.sourceRevision(),
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

  @Builder
  private OuterPagerBlocker() {
    Stack()
      .width('100%')
      .height('100%')
      .responseRegion(this.interactionFrame())
      .hitTestBehavior(HitTestMode.Transparent)
      .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) =>
        this.blockOuterHorizontalPager(recognizers))
  }

  @Builder
  private ArtworkSurface() {
    ArtworkView({
      sourceProvider: (): image.PixelMap | ResourceStr => this.source(),
      sourceRevision: this.sourceRevision(),
      sourceWidth: this.sourceWidth,
      sourceHeight: this.sourceHeight,
      slotWidth: this.artworkWidth(),
      slotAspectRatio: this.artworkAspectRatio(),
      fitMode: ArtworkFitMode.COVER,
      resolvedCornerRadius: this.sourceRadius(),
      shadowEnabled: true,
      shadowRadius: this.playbackShadowRadius(),
      shadowOffsetY: this.playbackShadowOffsetY(),
      interpolation: ImageInterpolation.Medium,
      onImageComplete: (): void => this.onArtworkReady(this.artworkActorGeneration),
      onImageError: (): void => this.onArtworkError(this.artworkActorGeneration)
    })
      .scale({
        x: this.playbackScale(),
        y: this.playbackScale()
      })
  }

  build() {
    Stack() {
      ForEach([this.sourceRevision()], (_sourceRevision: number): void => {
        this.ArtworkSurface()
      }, (sourceRevision: number): string => `${sourceRevision}`)
    }
    .width(this.artworkWidth())
    .height(this.artworkHeight())
    .renderFit(RenderFit.RESIZE_FILL)
    .opacity(this.contextMenuShown ? 0 : this.artworkOpacity())
    .position({ x: 0, y: 0 })
    .translate({ x: this.artworkX(), y: this.artworkY() })
    .accessibilityText('歌曲封面，长按打开更多操作')
    .onClick((): void => this.requestTap())
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
    .overlay(this.OuterPagerBlocker(), { align: Alignment.Center })
  }
}
