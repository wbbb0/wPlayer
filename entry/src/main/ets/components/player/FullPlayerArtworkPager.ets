import { curves, FrameCallback } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import {
  PlaybackArtworkLease,
  playbackRuntime
} from '../../playback/PlaybackRuntime';
import { LayoutLength } from '../layout/LayoutLength';
import {
  PlayerStore,
  QueueEntry,
  QueueIndexListener,
  QueuePositionSlot,
  QueueProjectionListener,
  QueueProjectionState,
  RepeatMode
} from '../../playback/model/PlaybackModels';
import { PlayerMorphArtwork } from './PlayerMorphArtwork';
import {
  PlayerArtworkImmersiveVisualBinding,
  PlayerArtworkSourceBinding,
  PlayerArtworkVisualBinding
} from './PlayerArtworkPlaybackVisualState';
import { FullPlayerArtworkSlotDataSource } from './FullPlayerArtworkSlotDataSource';
import {
  FullPlayerArtworkPagerCommand,
  FullPlayerArtworkPagerCommandKind,
  FullPlayerArtworkPagerCoordinator,
  FullPlayerArtworkGestureSequence,
  FullPlayerArtworkPagerPhase,
  FullPlayerArtworkPagerScrollMode
} from './FullPlayerArtworkPagerCoordinator';
import {
  FullPlayerArtworkStagePolicy,
  FullPlayerImmersivePhase
} from './FullPlayerArtworkStagePolicy';
import { FullPlayerImmersiveSplitMotion } from './FullPlayerImmersiveSplitMotion';
import {
  PlayerFrame,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec
} from './PlayerMotion';

@Component
struct FullPlayerArtworkPage {
  @ObjectLink slot: QueuePositionSlot;
  @ObjectLink @Watch('onProjectionChanged') projection: QueueProjectionState;
  @ObjectLink playbackVisual: PlayerArtworkVisualBinding;
  @ObjectLink immersiveVisual: PlayerArtworkImmersiveVisualBinding;
  @ObjectLink currentArtworkSource: PlayerArtworkSourceBinding;
  @ObjectLink immersiveSplitMotion: FullPlayerImmersiveSplitMotion;
  @Prop fullPlayerWidth: number = 0;
  @Prop fullPlayerHeight: number = 0;
  @Prop normalViewportX: number = 0;
  @Prop normalViewportY: number = 0;
  @Prop normalViewportWidth: number = 0;
  @Prop normalViewportHeight: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @ObjectLink coordinator: FullPlayerArtworkPagerCoordinator;
  onResolveArtwork: (relativePath: string) => string = (_relativePath: string): string => '';
  onArtworkReady: (queueEntryId: number, generation: number) => void =
    (_queueEntryId: number, _generation: number): void => {};
  onToggleImmersive: () => void = (): void => {};
  onInsertNext: () => void = (): void => {};
  onAppendToQueue: () => void = (): void => {};
  onAddToPlaylist: () => void = (): void => {};
  onOpenDetails: () => void = (): void => {};
  onShareTrackFile: () => void = (): void => {};
  onCompletedCollectionChange: (enabled: boolean) => void =
    (_enabled: boolean): void => {};
  isTrackAvailable: () => boolean = (): boolean => false;
  isCompletedCollectionEnabled: () => boolean = (): boolean => false;
  currentArtworkSourceProvider: () => image.PixelMap | ResourceStr =
    (): ResourceStr => $r('app.media.bundled_artwork_default_full');
  private artworkLease?: PlaybackArtworkLease;
  private artworkLeaseEntryId: number = -1;

  aboutToAppear(): void {
    this.reconcileArtworkLease();
  }

  aboutToDisappear(): void {
    this.releaseArtworkLease();
  }

  private onProjectionChanged(): void {
    this.reconcileArtworkLease();
  }

  private entry(): QueueEntry | undefined {
    return this.projection.entryAt(this.slot.index);
  }

  private fallbackArtworkSource(entry: QueueEntry): image.PixelMap | ResourceStr {
    if (this.artworkLeaseEntryId === entry.queueEntryId && this.artworkLease !== undefined) {
      return this.artworkLease.pixelMap;
    }
    const uri = this.onResolveArtwork(entry.track.largeArtworkPath);
    return uri.length > 0 ? uri : $r('app.media.bundled_artwork_default_full');
  }

  private artworkSource(entry: QueueEntry): image.PixelMap | ResourceStr {
    const fallback = this.fallbackArtworkSource(entry);
    if (!this.currentArtworkSource.matches(
      entry.track.largeArtworkHash,
      entry.track.largeArtworkPath
    )) {
      return fallback;
    }
    const current = this.currentArtworkSourceProvider();
    return current === fallback ? fallback : current;
  }

  private artworkSourceRevision(entry: QueueEntry): number {
    const usesCurrentSource = this.currentArtworkSource.matches(
      entry.track.largeArtworkHash,
      entry.track.largeArtworkPath
    ) && this.currentArtworkSourceProvider() !== this.fallbackArtworkSource(entry);
    return this.currentArtworkSource.actorRevision(
      entry.queueEntryId,
      entry.track.largeArtworkHash,
      entry.track.largeArtworkPath,
      usesCurrentSource
    );
  }

  private reconcileArtworkLease(): void {
    const entry = this.entry();
    if (entry !== undefined && entry.queueEntryId === this.artworkLeaseEntryId) {
      return;
    }
    this.releaseArtworkLease();
    if (entry === undefined) {
      return;
    }
    const lease = playbackRuntime.acquireCachedQueueArtwork(entry.track);
    if (lease !== undefined) {
      this.artworkLease = lease;
      this.artworkLeaseEntryId = entry.queueEntryId;
    }
  }

  private releaseArtworkLease(): void {
    this.artworkLease?.release();
    this.artworkLease = undefined;
    this.artworkLeaseEntryId = -1;
  }

  private immersiveFrame(entry: QueueEntry): PlayerFrame {
    const rootFrame: PlayerFrame = {
      x: 0,
      y: 0,
      width: this.fullPlayerWidth,
      height: this.fullPlayerHeight
    };
    const full = FullPlayerArtworkStagePolicy.immersiveFrame(
      rootFrame,
      this.topInset,
      this.bottomInset,
      entry.track.artworkWidth,
      entry.track.artworkHeight
    );
    const pane = FullPlayerArtworkStagePolicy.immersiveFrameInViewport({
      x: rootFrame.x,
      y: rootFrame.y,
      width: rootFrame.width / 2,
      height: rootFrame.height
    }, this.topInset, this.bottomInset, entry.track.artworkWidth, entry.track.artworkHeight);
    return FullPlayerArtworkStagePolicy.interpolateFrame(
      full, pane, this.immersiveSplitMotion.progress
    );
  }

  private normalViewportFrame(): PlayerFrame {
    return {
      x: this.normalViewportX,
      y: this.normalViewportY,
      width: this.normalViewportWidth,
      height: this.normalViewportHeight
    };
  }

  private immersiveViewportFrame(): PlayerFrame {
    const full: PlayerFrame = {
      x: 0,
      y: this.topInset,
      width: this.fullPlayerWidth,
      height: Math.max(1, this.fullPlayerHeight - this.topInset - this.bottomInset)
    };
    const split: PlayerFrame = {
      x: 0,
      y: this.topInset,
      width: this.fullPlayerWidth / 2,
      height: Math.max(1, this.fullPlayerHeight - this.topInset - this.bottomInset)
    };
    return FullPlayerArtworkStagePolicy.interpolateFrame(
      full, split, this.immersiveSplitMotion.progress
    );
  }

  private pagerClipFrame(): PlayerFrame {
    const viewport = FullPlayerArtworkStagePolicy.interpolateFrame(
      this.normalViewportFrame(),
      this.immersiveViewportFrame(),
      this.immersiveVisual.progress
    );
    return FullPlayerArtworkStagePolicy.shadowSafePagerFrame(
      viewport,
      PlayerMotionSpec.FULL_ARTWORK_SHADOW_RADIUS,
      PlayerMotionSpec.FULL_ARTWORK_SHADOW_OFFSET_Y
    );
  }

  private artworkFrame(entry: QueueEntry): PlayerFrame {
    const normal = FullPlayerArtworkStagePolicy.normalFrame(
      this.normalViewportFrame(),
      entry.track.artworkWidth,
      entry.track.artworkHeight
    );
    const target = FullPlayerArtworkStagePolicy.interpolateFrame(
      normal,
      this.immersiveFrame(entry),
      this.immersiveVisual.progress
    );
    return {
      x: target.x - this.pagerClipFrame().x,
      y: target.y - this.pagerClipFrame().y,
      width: target.width,
      height: target.height
    };
  }

  private actorKey(entry: QueueEntry): string {
    return `${entry.queueEntryId}:${entry.track.largeArtworkHash}:` +
      `${entry.track.largeArtworkPath}:${this.coordinator.readyGeneration}`;
  }

  @Builder
  private ArtworkActor(entry: QueueEntry, generation: number) {
    PlayerMorphArtwork({
      playbackVisual: this.playbackVisual,
      geometryProgress: 1,
      positionProgress: 1,
      elementOpacity: 1,
      frozenMiniPlayerFrame: { x: 0, y: 0, width: 0, height: 0 },
      fullPlayerArtworkTarget: this.artworkFrame(entry),
      sourceWidth: entry.track.artworkWidth,
      sourceHeight: entry.track.artworkHeight,
      artworkSourceRevision: this.artworkSourceRevision(entry),
      sourceProvider: (): image.PixelMap | ResourceStr => this.artworkSource(entry),
      artworkActorGeneration: generation,
      onArtworkReady: (actorGeneration: number): void =>
        this.onArtworkReady(entry.queueEntryId, actorGeneration),
      onArtworkError: (actorGeneration: number): void =>
        this.onArtworkReady(entry.queueEntryId, actorGeneration),
      onInsertNext: this.onInsertNext,
      onAppendToQueue: this.onAppendToQueue,
      onAddToPlaylist: this.onAddToPlaylist,
      onOpenDetails: this.onOpenDetails,
      onShareTrackFile: this.onShareTrackFile,
      onCompletedCollectionChange: this.onCompletedCollectionChange,
      isTrackAvailable: this.isTrackAvailable,
      isCompletedCollectionEnabled: this.isCompletedCollectionEnabled,
      onTap: this.onToggleImmersive
    })
  }

  build() {
    Stack() {
      if (this.entry() !== undefined) {
        ForEach([
          this.actorKey(this.entry() as QueueEntry)
        ], (_actorKey: string): void => {
          this.ArtworkActor(this.entry() as QueueEntry, this.coordinator.readyGeneration)
        }, (actorKey: string): string => actorKey)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}

@Component
export struct FullPlayerArtworkPager {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink coordinator: FullPlayerArtworkPagerCoordinator;
  @ObjectLink playbackVisual: PlayerArtworkVisualBinding;
  @ObjectLink immersiveVisual: PlayerArtworkImmersiveVisualBinding;
  @ObjectLink currentArtworkSource: PlayerArtworkSourceBinding;
  @ObjectLink @Watch('onSplitMotionChanged') immersiveSplitMotion: FullPlayerImmersiveSplitMotion;
  @Prop fullPlayerWidth: number = 0;
  @Prop fullPlayerHeight: number = 0;
  @Prop normalViewportX: number = 0;
  @Prop normalViewportY: number = 0;
  @Prop normalViewportWidth: number = 0;
  @Prop normalViewportHeight: number = 0;
  @Prop @Watch('onPlayerMorphPhaseChanged') playerMorphPhase: PlayerMorphPhase =
    PlayerMorphPhase.IDLE;
  @Prop @Watch('onImmersivePhaseChanged') immersivePhase: FullPlayerImmersivePhase =
    FullPlayerImmersivePhase.NORMAL;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop artworkResponseFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  // Native Swiper owns in-flight presentation; this mirror must not rebuild it on settle.
  private pagerIndex: number = 0;
  private readonly swiperController: SwiperController = new SwiperController();
  private readonly slotDataSource: FullPlayerArtworkSlotDataSource =
    new FullPlayerArtworkSlotDataSource();
  private mounted: boolean = false;
  private reanchorEpoch: number = 0;
  private adjacentPreloadEpoch: number = 0;
  private measuredWidth: number = 0;
  private measuredHeight: number = 0;
  private splitMotionActive: boolean = false;
  private visualScrolling: boolean = false;
  @State adjacentPreloadEnabled: boolean = false;
  private readonly gestureSequence: FullPlayerArtworkGestureSequence =
    new FullPlayerArtworkGestureSequence();
  private readonly projectionListener: QueueProjectionListener = (): void =>
    this.handleProjectionChanged();
  private readonly queueIndexListener: QueueIndexListener = (index: number): void =>
    this.handleQueueIndexChanged(index);
  onResolveArtwork: (relativePath: string) => string = (_relativePath: string): string => '';
  currentArtworkSourceProvider: () => image.PixelMap | ResourceStr =
    (): ResourceStr => $r('app.media.bundled_artwork_default_full');
  onToggleImmersive: () => void = (): void => {};
  onInsertNext: () => void = (): void => {};
  onAppendToQueue: () => void = (): void => {};
  onAddToPlaylist: () => void = (): void => {};
  onOpenDetails: () => void = (): void => {};
  onShareTrackFile: () => void = (): void => {};
  onCompletedCollectionChange: (enabled: boolean) => void =
    (_enabled: boolean): void => {};
  onScrollingChange: (active: boolean) => void = (_active: boolean): void => {};

  aboutToAppear(): void {
    this.mounted = true;
    const entries = this.entries();
    const currentIndex = this.playerStore.queueDataSource.projectionState.activeIndex();
    this.slotDataSource.syncCount(entries.length);
    this.coordinator.initialize(entries, currentIndex);
    this.pagerIndex = this.coordinator.initialIndex(entries, currentIndex);
    this.splitMotionActive = this.immersiveSplitMotion.isActive();
    this.adjacentPreloadEnabled = false;
    this.playerStore.queueDataSource.addProjectionListener(this.projectionListener);
    this.playerStore.addQueueIndexListener(this.queueIndexListener);
  }

  aboutToDisappear(): void {
    this.setVisualScrolling(false);
    this.mounted = false;
    this.reanchorEpoch += 1;
    this.adjacentPreloadEpoch += 1;
    this.adjacentPreloadEnabled = false;
    this.playerStore.queueDataSource.removeProjectionListener(this.projectionListener);
    this.playerStore.removeQueueIndexListener(this.queueIndexListener);
    this.coordinator.dispose();
  }

  private entries(): Array<QueueEntry> {
    return this.playerStore.queueDataSource.snapshot();
  }

  private handleProjectionChanged(): void {
    if (!this.mounted) {
      return;
    }
    this.disableAdjacentPreload();
    const command = this.coordinator.onProjectionChanged(
      this.entries(),
      this.playerStore.queueDataSource.projectionState.activeIndex()
    );
    this.slotDataSource.syncCount(this.playerStore.queueDataSource.totalCount());
    this.scheduleReanchor(command);
  }

  private handleQueueIndexChanged(index: number): void {
    if (!this.mounted) {
      return;
    }
    this.execute(this.coordinator.onQueueIndexChanged(this.entries(), index, this.looping()));
  }

  private execute(command: FullPlayerArtworkPagerCommand): void {
    if (command.kind === FullPlayerArtworkPagerCommandKind.SELECT_ENTRY) {
      playbackRuntime.selectQueueEntryPreservingPlaybackIntent(command.queueEntryId);
      return;
    }
    if (command.kind !== FullPlayerArtworkPagerCommandKind.CHANGE_INDEX) {
      return;
    }
    if (command.scrollMode === FullPlayerArtworkPagerScrollMode.NONE) {
      this.pagerIndex = command.index;
      this.swiperController.changeIndex(command.index, SwiperAnimationMode.NO_ANIMATION);
      const revealed = this.coordinator.onReanchorApplied(
        command.queueEntryId,
        this.coordinator.readyGeneration
      );
      if (revealed) {
        this.scheduleAdjacentPreload();
      }
      return;
    }
    const animationMode = command.scrollMode === FullPlayerArtworkPagerScrollMode.FAST ?
      SwiperAnimationMode.FAST_ANIMATION : SwiperAnimationMode.DEFAULT_ANIMATION;
    this.swiperController.changeIndex(command.index, animationMode);
  }

  private scheduleReanchor(command: FullPlayerArtworkPagerCommand): void {
    if (command.kind !== FullPlayerArtworkPagerCommandKind.CHANGE_INDEX ||
      command.scrollMode !== FullPlayerArtworkPagerScrollMode.NONE) {
      this.execute(command);
      return;
    }
    const epoch = ++this.reanchorEpoch;
    const callback: FrameCallback = {
      onFrame: (_frameTimeInNano: number): void => {
        if (!this.mounted || epoch !== this.reanchorEpoch) {
          return;
        }
        this.execute(command);
      },
      onIdle: (_timeLeftInNano: number): void => {}
    };
    this.getUIContext().postFrameCallback(callback);
  }

  private handleAnimationStart(targetIndex: number): void {
    // Keep the bound index at the last settled page while native Swiper owns
    // the release animation. Publishing the target here turns the rerender
    // caused by coordinator state into an immediate external index change.
    this.coordinator.onAnimationStart(this.entries(), targetIndex);
    this.setVisualScrolling(true);
  }

  private handleAnimationEnd(index: number): void {
    const accepted = this.coordinator.acceptsAnimationEnd(this.entries(), index);
    if (accepted) {
      this.pagerIndex = index;
    }
    const continuation = this.coordinator.onAnimationEnd(this.entries(), index, this.looping());
    this.gestureSequence.onAnimationEnd();
    this.execute(continuation);
    this.setVisualScrolling(this.coordinator.isMotionActive());
  }

  private handleUserGesture(): void {
    if (!this.gestureSequence.consumeSwipeFrame()) {
      return;
    }
    this.coordinator.onUserGesture();
    this.setVisualScrolling(true);
  }

  private setVisualScrolling(active: boolean): void {
    if (this.visualScrolling === active) {
      return;
    }
    this.visualScrolling = active;
    this.onScrollingChange(active);
  }

  private handleTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.gestureSequence.onTouchDown();
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.gestureSequence.onTouchEnd();
    }
  }

  private looping(): boolean {
    return this.playerStore.repeatMode === RepeatMode.ALL;
  }

  private handleArtworkReady(queueEntryId: number, generation: number): void {
    const revealed = this.coordinator.onPageReady(queueEntryId, generation);
    if (revealed) {
      this.scheduleAdjacentPreload();
    }
  }

  private onPlayerMorphPhaseChanged(): void {
    if (this.playerMorphPhase !== PlayerMorphPhase.OPEN) {
      this.disableAdjacentPreload();
      return;
    }
    this.scheduleAdjacentPreload();
  }

  private disableAdjacentPreload(): void {
    this.adjacentPreloadEpoch += 1;
    if (this.adjacentPreloadEnabled) {
      this.adjacentPreloadEnabled = false;
    }
  }

  private scheduleAdjacentPreload(): void {
    if (!this.mounted || this.adjacentPreloadEnabled ||
      !FullPlayerArtworkStagePolicy.shouldPreloadAdjacentArtwork(
        this.playerMorphPhase,
        this.coordinator.pagerVisible
      )) {
      return;
    }
    const epoch = ++this.adjacentPreloadEpoch;
    const callback: FrameCallback = {
      onFrame: (_frameTimeInNano: number): void => {
        if (!this.mounted || epoch !== this.adjacentPreloadEpoch ||
          !FullPlayerArtworkStagePolicy.shouldPreloadAdjacentArtwork(
            this.playerMorphPhase,
            this.coordinator.pagerVisible
          )) {
          return;
        }
        this.adjacentPreloadEnabled = true;
      },
      onIdle: (_timeLeftInNano: number): void => {}
    };
    this.getUIContext().postFrameCallback(callback);
  }

  private pagingDisabled(): boolean {
    return this.playerMorphPhase !== PlayerMorphPhase.OPEN ||
      this.immersivePhase === FullPlayerImmersivePhase.ENTERING ||
      this.immersivePhase === FullPlayerImmersivePhase.EXITING ||
      this.immersiveSplitMotion.isActive() ||
      !this.coordinator.allowsUserSwipe() ||
      this.playerStore.queueSize <= 1;
  }

  private onImmersivePhaseChanged(): void {
    if (this.immersivePhase === FullPlayerImmersivePhase.NORMAL ||
      this.immersivePhase === FullPlayerImmersivePhase.IMMERSIVE) {
      this.syncViewportAnchor();
    }
  }

  private onSplitMotionChanged(): void {
    const active = this.immersiveSplitMotion.isActive();
    const completed = this.splitMotionActive && !active;
    this.splitMotionActive = active;
    if (completed) {
      this.syncViewportAnchor();
    }
  }

  private syncViewportAnchor(): void {
    if (!this.mounted || this.coordinator.phase !== FullPlayerArtworkPagerPhase.IDLE) {
      return;
    }
    const activeIndex = this.playerStore.queueDataSource.projectionState.activeIndex();
    if (activeIndex >= 0) {
      this.swiperController.changeIndex(activeIndex, SwiperAnimationMode.NO_ANIMATION);
    }
  }

  private handleViewportChanged(area: Area): void {
    const width = LayoutLength.toNumber(area.width, this.measuredWidth);
    const height = LayoutLength.toNumber(area.height, this.measuredHeight);
    if (width <= 0 || height <= 0) {
      return;
    }
    const changed = Math.abs(width - this.measuredWidth) > 0.5 ||
      Math.abs(height - this.measuredHeight) > 0.5;
    this.measuredWidth = width;
    this.measuredHeight = height;
    if (!changed || this.pagingDisabled()) {
      return;
    }
    this.syncViewportAnchor();
  }

  build() {
    Swiper(this.swiperController) {
      LazyForEach(this.slotDataSource, (slot: QueuePositionSlot): void => {
        FullPlayerArtworkPage({
          slot: slot,
          projection: this.playerStore.queueDataSource.projectionState,
          playbackVisual: this.playbackVisual,
          immersiveVisual: this.immersiveVisual,
          currentArtworkSource: this.currentArtworkSource,
          immersiveSplitMotion: this.immersiveSplitMotion,
          fullPlayerWidth: this.fullPlayerWidth,
          fullPlayerHeight: this.fullPlayerHeight,
          normalViewportX: this.normalViewportX,
          normalViewportY: this.normalViewportY,
          normalViewportWidth: this.normalViewportWidth,
          normalViewportHeight: this.normalViewportHeight,
          coordinator: this.coordinator,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          currentArtworkSourceProvider: this.currentArtworkSourceProvider,
          onResolveArtwork: this.onResolveArtwork,
          onArtworkReady: (queueEntryId: number, generation: number): void =>
            this.handleArtworkReady(queueEntryId, generation),
          onToggleImmersive: this.onToggleImmersive,
          onInsertNext: this.onInsertNext,
          onAppendToQueue: this.onAppendToQueue,
          onAddToPlaylist: this.onAddToPlaylist,
          onOpenDetails: this.onOpenDetails,
          onShareTrackFile: this.onShareTrackFile,
          onCompletedCollectionChange: this.onCompletedCollectionChange,
          isTrackAvailable: (): boolean => this.playerStore.currentTrack !== undefined,
          isCompletedCollectionEnabled: (): boolean =>
            this.playerStore.completedCollectionEnabled
        })
      }, (slot: QueuePositionSlot): string => `artwork-slot:${slot.index}`)
    }
    .index(this.pagerIndex)
    .indicator(false)
    .loop(this.looping())
    .itemSpace(PlayerLayoutSpec.FULL_PLAYER_ARTWORK_PAGE_GAP)
    .curve(curves.springMotion(
      PlayerMotionSpec.ARTWORK_PAGER_SPRING_RESPONSE,
      PlayerMotionSpec.ARTWORK_PAGER_SPRING_DAMPING
    ))
    .cachedCount(this.adjacentPreloadEnabled ? 1 : 0, this.adjacentPreloadEnabled)
    .disableSwipe(this.pagingDisabled())
    .responseRegion({
      x: this.artworkResponseFrame.x,
      y: this.artworkResponseFrame.y,
      width: this.artworkResponseFrame.width,
      height: this.artworkResponseFrame.height
    })
    .width('100%')
    .height('100%')
    .visibility(this.coordinator.pagerVisible ? Visibility.Visible : Visibility.Hidden)
    .onAnimationStart((_index: number, targetIndex: number): void =>
      this.handleAnimationStart(targetIndex))
    .onAnimationEnd((index: number): void => this.handleAnimationEnd(index))
    .onGestureSwipe((_index: number): void => this.handleUserGesture())
    .onTouch((event: TouchEvent): void => this.handleTouch(event))
    .onAreaChange((_oldValue: Area, newValue: Area): void => this.handleViewportChanged(newValue))
  }
}
