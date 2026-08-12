import { FrameCallback } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
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
import { PlayerMorphController } from './PlayerMorphController';
import { PlayerArtworkVisualBinding } from './PlayerArtworkPlaybackVisualState';
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
  PlayerMorphPhase,
  PlayerMotionSpec
} from './PlayerMotion';

@Component
struct FullPlayerArtworkPage {
  @ObjectLink slot: QueuePositionSlot;
  @ObjectLink projection: QueueProjectionState;
  @ObjectLink playbackVisual: PlayerArtworkVisualBinding;
  @ObjectLink controller: PlayerMorphController;
  @ObjectLink immersiveSplitMotion: FullPlayerImmersiveSplitMotion;
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

  private entry(): QueueEntry | undefined {
    return this.projection.entryAt(this.slot.index);
  }

  private artworkSource(entry: QueueEntry): ResourceStr {
    const uri = this.onResolveArtwork(entry.track.largeArtworkPath);
    return uri.length > 0 ? uri : $r('app.media.bundled_artwork_default_full');
  }

  private immersiveFrame(entry: QueueEntry): PlayerFrame {
    const rootFrame = this.controller.fullPlayerFrame();
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
    const outerOffset = this.controller.fullPlayerArtworkTarget().x -
      this.controller.centeredArtworkTarget.x;
    return {
      x: this.controller.artworkViewportTarget.x + outerOffset,
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
      full, split, this.immersiveSplitMotion.progress
    );
  }

  private pagerClipFrame(): PlayerFrame {
    const viewport = FullPlayerArtworkStagePolicy.interpolateFrame(
      this.normalViewportFrame(),
      this.immersiveViewportFrame(),
      this.controller.effectiveFullPlayerImmersiveProgress()
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
      this.controller.effectiveFullPlayerImmersiveProgress()
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
      artworkSourceRevision: entry.queueEntryId,
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
  @ObjectLink controller: PlayerMorphController;
  @ObjectLink @Watch('onSplitMotionChanged') immersiveSplitMotion: FullPlayerImmersiveSplitMotion;
  @Prop playerMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
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
  private measuredWidth: number = 0;
  private measuredHeight: number = 0;
  private splitMotionActive: boolean = false;
  private readonly gestureSequence: FullPlayerArtworkGestureSequence =
    new FullPlayerArtworkGestureSequence();
  private readonly projectionListener: QueueProjectionListener = (): void =>
    this.handleProjectionChanged();
  private readonly queueIndexListener: QueueIndexListener = (index: number): void =>
    this.handleQueueIndexChanged(index);
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
    const entries = this.entries();
    const currentIndex = this.playerStore.queueDataSource.projectionState.activeIndex();
    this.slotDataSource.syncCount(entries.length);
    this.coordinator.initialize(entries, currentIndex);
    this.pagerIndex = this.coordinator.initialIndex(entries, currentIndex);
    this.splitMotionActive = this.immersiveSplitMotion.isActive();
    this.playerStore.queueDataSource.addProjectionListener(this.projectionListener);
    this.playerStore.addQueueIndexListener(this.queueIndexListener);
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.reanchorEpoch += 1;
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
      this.coordinator.onReanchorApplied(
        command.queueEntryId,
        this.coordinator.readyGeneration
      );
    } else if (command.scrollMode === FullPlayerArtworkPagerScrollMode.FAST) {
      this.pagerIndex = command.index;
      this.swiperController.changeIndex(command.index, SwiperAnimationMode.FAST_ANIMATION);
    } else {
      this.pagerIndex = command.index;
      this.swiperController.changeIndex(command.index, SwiperAnimationMode.DEFAULT_ANIMATION);
    }
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
    this.pagerIndex = targetIndex;
    this.coordinator.onAnimationStart(this.entries(), targetIndex);
  }

  private handleAnimationEnd(index: number): void {
    if (this.coordinator.acceptsAnimationEnd(this.entries(), index)) {
      this.pagerIndex = index;
    }
    this.execute(this.coordinator.onAnimationEnd(this.entries(), index, this.looping()));
    this.gestureSequence.onAnimationEnd();
  }

  private handleUserGesture(): void {
    if (!this.gestureSequence.consumeSwipeFrame()) {
      return;
    }
    this.coordinator.onUserGesture();
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
    this.coordinator.onPageReady(queueEntryId, generation);
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
          controller: this.controller,
          immersiveSplitMotion: this.immersiveSplitMotion,
          coordinator: this.coordinator,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
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
    .cachedCount(1, true)
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
