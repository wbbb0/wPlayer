import { curves } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { PlayerMorphArtwork } from './PlayerMorphArtwork';
import { FullPlayerArtworkPager } from './FullPlayerArtworkPager';
import { FullPlayerArtworkPagerCoordinator } from './FullPlayerArtworkPagerCoordinator';
import { PlayerMorphController } from './PlayerMorphController';
import { FullPlayerArtworkStagePolicy } from './FullPlayerArtworkStagePolicy';
import { FullPlayerImmersiveSplitMotion } from './FullPlayerImmersiveSplitMotion';
import {
  PlayerArtworkPlaybackVisualAction,
  PlayerArtworkPlaybackVisualState,
  PlayerArtworkSourceBinding,
  PlayerArtworkVisualBinding
} from './PlayerArtworkPlaybackVisualState';
import {
  PlayerFrame,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec
} from './PlayerMotion';

@Component
export struct FullPlayerArtworkStage {
  @ObjectLink controller: PlayerMorphController;
  @ObjectLink @Watch('onPlayerStoreChanged') playerStore: PlayerStore;
  @ObjectLink immersiveSplitMotion: FullPlayerImmersiveSplitMotion;
  @Prop @Watch('onMorphPhaseChanged') morphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop geometryProgress: number = 0;
  @Prop positionProgress: number = 0;
  @Prop elementOpacity: number = 1;
  @Prop frozenMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  @State pagerCoordinator: FullPlayerArtworkPagerCoordinator =
    new FullPlayerArtworkPagerCoordinator();
  @State playbackVisual: PlayerArtworkVisualBinding = new PlayerArtworkVisualBinding();
  @State artworkSource: PlayerArtworkSourceBinding = new PlayerArtworkSourceBinding();
  @State pagerScrolling: boolean = false;
  @State closeHandoffActive: boolean = false;
  @State closeActorReady: boolean = false;
  @State actorReadyRevision: number = -1;
  private readonly playbackVisualState: PlayerArtworkPlaybackVisualState =
    new PlayerArtworkPlaybackVisualState();
  private mounted: boolean = false;
  private previousMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  private playbackVisualAnimationEpoch: number = 0;
  private playbackVisualAnimating: boolean = false;
  sourceProvider: () => image.PixelMap | ResourceStr =
    (): ResourceStr => $r('app.media.bundled_artwork_default_full');
  onResolveArtwork: (relativePath: string) => string = (_relativePath: string): string => '';
  onToggleImmersive: () => void = (): void => {};
  onInsertNext: () => void = (): void => {};
  onAppendToQueue: () => void = (): void => {};
  onAddToPlaylist: () => void = (): void => {};
  onOpenDetails: () => void = (): void => {};
  onShareTrackFile: () => void = (): void => {};
  onCompletedCollectionChange: (enabled: boolean) => void =
    (_enabled: boolean): void => {};

  aboutToAppear(): void {
    this.mounted = true;
    this.previousMorphPhase = this.morphPhase;
    this.playbackVisualState.reset(this.currentPlaybackVisualTarget());
    this.playbackVisual.progress = this.playbackVisualState.value();
    this.syncArtworkSource();
    this.syncArtworkMotionActivity();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.playbackVisualAnimationEpoch += 1;
    this.playbackVisualAnimating = false;
    this.pagerScrolling = false;
  }

  private currentPlaybackVisualTarget(): number {
    return PlayerMotionSpec.artworkPlaybackVisualTarget(
      this.playerStore.keepsActivePlaybackVisual()
    );
  }

  private onPlayerStoreChanged(): void {
    this.syncArtworkSource();
    const target = this.currentPlaybackVisualTarget();
    if (!this.mounted) {
      this.playbackVisualState.reset(target);
      this.playbackVisual.progress = this.playbackVisualState.value();
      return;
    }
    this.applyPlaybackVisualAction(
      this.playbackVisualState.updateTarget(target, this.morphPhase)
    );
  }

  private syncArtworkSource(): void {
    const track = this.playerStore.currentTrack;
    this.artworkSource.sync(
      track?.largeArtworkHash ?? '',
      track?.largeArtworkPath ?? '',
      this.playerStore.heroArtworkRevision
    );
  }

  private onMorphPhaseChanged(): void {
    const previous = this.previousMorphPhase;
    this.previousMorphPhase = this.morphPhase;
    if (this.morphPhase !== PlayerMorphPhase.OPEN && this.pagerScrolling) {
      this.pagerScrolling = false;
    }
    if (this.morphPhase !== PlayerMorphPhase.OPEN && this.playbackVisualAnimating) {
      this.playbackVisualAnimationEpoch += 1;
      this.playbackVisualAnimating = false;
    }
    this.syncArtworkMotionActivity();
    if (previous === PlayerMorphPhase.OPEN && this.morphPhase !== PlayerMorphPhase.OPEN) {
      this.closeHandoffActive = true;
      this.closeActorReady = this.actorReadyRevision === this.actorSourceRevision();
    } else if ((this.morphPhase === PlayerMorphPhase.OPEN ||
      this.morphPhase === PlayerMorphPhase.IDLE) &&
      (this.closeHandoffActive || this.closeActorReady)) {
      this.closeHandoffActive = false;
      this.closeActorReady = false;
    }
    if (!this.mounted) {
      return;
    }
    this.applyPlaybackVisualAction(
      this.playbackVisualState.updatePhase(this.morphPhase)
    );
  }

  private applyPlaybackVisualAction(action: PlayerArtworkPlaybackVisualAction): void {
    if (action !== PlayerArtworkPlaybackVisualAction.ANIMATE_TO_TARGET) {
      return;
    }
    const target = this.playbackVisualState.value();
    const epoch = ++this.playbackVisualAnimationEpoch;
    this.playbackVisualAnimating = true;
    this.syncArtworkMotionActivity();
    this.getUIContext().animateTo({
      curve: curves.springMotion(
        PlayerMotionSpec.ARTWORK_STATE_SPRING_RESPONSE,
        PlayerMotionSpec.ARTWORK_STATE_SPRING_DAMPING
      ),
      onFinish: (): void => {
        if (!this.mounted || epoch !== this.playbackVisualAnimationEpoch) {
          return;
        }
        this.playbackVisualAnimating = false;
        this.syncArtworkMotionActivity();
      }
    }, () => {
      this.playbackVisual.progress = target;
    });
  }

  private setPagerScrolling(active: boolean): void {
    this.pagerScrolling = active;
    this.syncArtworkMotionActivity();
  }

  private syncArtworkMotionActivity(): void {
    this.controller.setFullPlayerArtworkMotionActive(
      this.pagerScrolling || this.playbackVisualAnimating
    );
  }

  private immersiveFrame(sourceWidth: number, sourceHeight: number): PlayerFrame {
    const root = this.controller.fullPlayerFrame();
    const full = FullPlayerArtworkStagePolicy.immersiveFrame(
      root, this.topInset, this.bottomInset, sourceWidth, sourceHeight
    );
    const pane = FullPlayerArtworkStagePolicy.immersiveFrameInViewport({
      x: root.x,
      y: root.y,
      width: root.width / 2,
      height: root.height
    }, this.topInset, this.bottomInset, sourceWidth, sourceHeight);
    return FullPlayerArtworkStagePolicy.interpolateFrame(
      full,
      pane,
      this.immersiveSplitMotion.progress
    );
  }

  private normalViewportFrame(): PlayerFrame {
    return {
      x: this.controller.artworkViewportTarget.x,
      y: this.controller.artworkViewportTarget.y,
      width: this.controller.artworkViewportTarget.width,
      height: this.controller.artworkViewportTarget.height
    };
  }

  private immersiveViewportFrame(): PlayerFrame {
    const root = this.controller.fullPlayerFrame();
    const full: PlayerFrame = {
      x: root.x,
      y: root.y + this.topInset,
      width: root.width,
      height: Math.max(1, root.height - this.topInset - this.bottomInset)
    };
    const split: PlayerFrame = {
      x: root.x,
      y: root.y + this.topInset,
      width: root.width / 2,
      height: Math.max(1, root.height - this.topInset - this.bottomInset)
    };
    return FullPlayerArtworkStagePolicy.interpolateFrame(
      full,
      split,
      this.immersiveSplitMotion.progress
    );
  }

  private pagerViewportFrame(): PlayerFrame {
    return FullPlayerArtworkStagePolicy.interpolateFrame(
      this.normalViewportFrame(),
      this.immersiveViewportFrame(),
      this.controller.effectiveFullPlayerImmersiveProgress()
    );
  }

  private pagerClipFrame(): PlayerFrame {
    return FullPlayerArtworkStagePolicy.shadowSafePagerFrame(
      this.pagerViewportFrame(),
      PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS,
      PlayerMotionSpec.FULL_ARTWORK_SHADOW_OFFSET_Y
    );
  }

  private pagerPageOffsetX(): number {
    return this.controller.fullPlayerArtworkTarget().x -
      this.controller.centeredArtworkTarget.x;
  }

  private presentedPagerClipFrame(): PlayerFrame {
    const clip = this.pagerClipFrame();
    return {
      x: clip.x + this.pagerPageOffsetX(),
      y: clip.y,
      width: clip.width,
      height: clip.height
    };
  }

  private actorHostFrame(): PlayerFrame {
    if (this.morphPhase === PlayerMorphPhase.OPEN) {
      return this.pagerClipFrame();
    }
    if (this.morphPhase === PlayerMorphPhase.IDLE) {
      const root = this.controller.rootFrame;
      return { x: root.x, y: root.y, width: root.width, height: root.height };
    }
    const root = this.controller.fullPlayerFrame();
    return { x: root.x, y: root.y, width: root.width, height: root.height };
  }

  private frameRelativeTo(frame: PlayerFrame, viewport: PlayerFrame): PlayerFrame {
    return {
      x: frame.x - viewport.x,
      y: frame.y - viewport.y,
      width: frame.width,
      height: frame.height
    };
  }

  private currentTarget(): PlayerFrame {
    const normal = this.controller.fullPlayerArtworkTarget();
    const immersive = this.immersiveFrame(
      this.controller.morphArtworkSourceWidth(),
      this.controller.morphArtworkSourceHeight()
    );
    return FullPlayerArtworkStagePolicy.interpolateFrame(
      normal,
      immersive,
      this.controller.effectiveFullPlayerImmersiveProgress()
    );
  }

  private artworkResponseFrame(): PlayerFrame {
    const target = FullPlayerArtworkStagePolicy.scaledFrame(
      this.currentTarget(),
      PlayerMotionSpec.artworkPlaybackVisualValue(
        PlayerMotionSpec.PAUSED_ARTWORK_SCALE,
        1,
        this.playbackVisual.progress
      )
    );
    return this.frameRelativeTo(target, this.presentedPagerClipFrame());
  }

  private stablePagerVisible(): boolean {
    return this.morphPhase === PlayerMorphPhase.OPEN && this.pagerCoordinator.pagerVisible;
  }

  private pagerVisible(): boolean {
    return FullPlayerArtworkStagePolicy.shouldShowPager(
      this.morphPhase,
      this.pagerCoordinator.pagerVisible,
      this.closeHandoffActive,
      this.closeActorReady
    );
  }

  private morphActorOpacity(): number {
    return FullPlayerArtworkStagePolicy.morphActorOpacity(
      this.morphPhase,
      this.stablePagerVisible(),
      this.elementOpacity
    );
  }

  private morphActorInteractionEnabled(): boolean {
    return FullPlayerArtworkStagePolicy.shouldEnableMorphActorInteraction(
      this.morphPhase,
      this.stablePagerVisible()
    );
  }

  private actorSourceRevision(): number {
    return this.controller.morphArtworkSourceRevision();
  }

  private pagerEdgeMasksActive(): boolean {
    return FullPlayerArtworkStagePolicy.shouldApplyPagerEdgeMasks(this.pagerScrolling);
  }

  private completeArtworkPreparation(sourceRevision: number): void {
    if (sourceRevision !== this.actorSourceRevision()) {
      return;
    }
    this.actorReadyRevision = sourceRevision;
    if (this.closeHandoffActive) {
      this.closeActorReady = true;
    }
  }

  @Builder
  private MorphActor() {
    PlayerMorphArtwork({
      playbackVisual: this.playbackVisual,
      geometryProgress: this.geometryProgress,
      positionProgress: this.positionProgress,
      elementOpacity: this.morphActorOpacity(),
      frozenMiniPlayerFrame: this.frameRelativeTo(
        this.frozenMiniPlayerFrame,
        this.actorHostFrame()
      ),
      fullPlayerArtworkTarget: this.frameRelativeTo(
        this.currentTarget(),
        this.actorHostFrame()
      ),
      sourceWidth: this.controller.morphArtworkSourceWidth(),
      sourceHeight: this.controller.morphArtworkSourceHeight(),
      artworkSourceRevision: this.actorSourceRevision(),
      sourceProvider: this.sourceProvider,
      artworkActorGeneration: this.actorSourceRevision(),
      onArtworkReady: (sourceRevision: number): void =>
        this.completeArtworkPreparation(sourceRevision),
      onArtworkError: (_sourceRevision: number): void => {},
      onInsertNext: this.onInsertNext,
      onAppendToQueue: this.onAppendToQueue,
      onAddToPlaylist: this.onAddToPlaylist,
      onOpenDetails: this.onOpenDetails,
      onShareTrackFile: this.onShareTrackFile,
      onCompletedCollectionChange: this.onCompletedCollectionChange,
      isTrackAvailable: (): boolean => this.playerStore.currentTrack !== undefined,
      isCompletedCollectionEnabled: (): boolean =>
        this.playerStore.completedCollectionEnabled,
      interactionEnabled: this.morphActorInteractionEnabled(),
      onTap: this.onToggleImmersive
    })
  }

  @Builder
  private PagerAlphaEdgeMasks() {
    Stack() {
      Row()
        .width(PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET)
        .height('100%')
        .position({ x: 0, y: 0 })
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [[Color.Black, 0], [Color.Transparent, 1]]
        })
        .blendMode(BlendMode.DST_OUT)
      Row()
        .width(PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET)
        .height('100%')
        .position({
          x: Math.max(0, this.pagerClipFrame().width -
            PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET),
          y: 0
        })
        .linearGradient({
          direction: GradientDirection.Left,
          colors: [[Color.Black, 0], [Color.Transparent, 1]]
        })
        .blendMode(BlendMode.DST_OUT)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    Stack() {
      Stack() {
        this.MorphActor()
      }
      .width(this.actorHostFrame().width)
      .height(this.actorHostFrame().height)
      .position({ x: 0, y: 0 })
      .translate({ x: this.actorHostFrame().x, y: this.actorHostFrame().y })
      .clip(this.morphPhase === PlayerMorphPhase.OPEN)
      .hitTestBehavior(this.morphActorInteractionEnabled() ?
        HitTestMode.Default : HitTestMode.Transparent)
      .zIndex(1)

      if (FullPlayerArtworkStagePolicy.shouldMountPager(this.morphPhase)) {
        Stack() {
          FullPlayerArtworkPager({
            playerStore: this.playerStore,
            coordinator: this.pagerCoordinator,
            playbackVisual: this.playbackVisual,
            immersiveVisual: this.controller.fullPlayerArtworkImmersiveVisual,
            currentArtworkSource: this.artworkSource,
            immersiveSplitMotion: this.immersiveSplitMotion,
            fullPlayerWidth: this.controller.fullPlayerFrame().width,
            fullPlayerHeight: this.controller.fullPlayerFrame().height,
            normalViewportX: this.normalViewportFrame().x,
            normalViewportY: this.normalViewportFrame().y,
            normalViewportWidth: this.normalViewportFrame().width,
            normalViewportHeight: this.normalViewportFrame().height,
            playerMorphPhase: this.morphPhase,
            immersivePhase: this.controller.fullPlayerImmersivePhase,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            artworkResponseFrame: this.artworkResponseFrame(),
            currentArtworkSourceProvider: this.sourceProvider,
            onResolveArtwork: this.onResolveArtwork,
            onToggleImmersive: this.onToggleImmersive,
            onInsertNext: this.onInsertNext,
            onAppendToQueue: this.onAppendToQueue,
            onAddToPlaylist: this.onAddToPlaylist,
            onOpenDetails: this.onOpenDetails,
            onShareTrackFile: this.onShareTrackFile,
            onCompletedCollectionChange: this.onCompletedCollectionChange,
            onScrollingChange: (active: boolean): void => {
              this.setPagerScrolling(active);
            }
          })
          if (this.pagerEdgeMasksActive()) {
            this.PagerAlphaEdgeMasks()
          }
        }
        .width(this.pagerClipFrame().width)
        .height(this.pagerClipFrame().height)
        .position({ x: 0, y: 0 })
        .translate({
          x: this.presentedPagerClipFrame().x,
          y: this.presentedPagerClipFrame().y
        })
        .clip(true)
        .visibility(this.pagerVisible() ? Visibility.Visible : Visibility.Hidden)
        .blendMode(
          BlendMode.SRC_OVER,
          this.pagerEdgeMasksActive() ? BlendApplyType.OFFSCREEN : BlendApplyType.FAST
        )
        .zIndex(0)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
