import { FrameCallback } from '@kit.ArkUI';
import { TitleBarMotionSpec } from '../navigation/TitleBarMotionSpec';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import {
  PlayerStore,
  QueueEntry,
  QueueIndexListener,
  QueuePositionSlot,
  QueueProjectionListener,
  QueueProjectionState,
  QueueTrack
} from '../../playback/model/PlaybackModels';
import {
  AvailabilityState,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import {
  DragSelectionController,
  DragSelectionHitMode
} from '../library/DragSelectionController';
import {
  PlayerModeAction,
  PlayerModeButton,
  PlayerSymbolIcon
} from './PlayerControls';
import {
  PlayerQueueSelectionMenu,
  PlayerQueueSelectionMenuParams
} from './PlayerActionMenus';
import { QueueTrackRow } from './QueueTrackRow';
import {
  FULL_PLAYER_VERTICAL_GESTURE_HOST_ID,
  FullPlayerListFocusState,
  PlayerLayoutSpec,
  PlayerMotionSpec
} from './PlayerMotion';
import {
  FullPlayerQueueRefreshPhase,
  FullPlayerQueueRefreshState
} from './FullPlayerQueueRefreshState';

class QueueRefreshFrameCallback extends FrameCallback {
  private readonly onIdleFrame: () => void;

  constructor(onIdleFrame: () => void) {
    super();
    this.onIdleFrame = onIdleFrame;
  }

  onFrame(_frameTimeInNano: number): void {
  }

  onIdle(_timeLeftInNano: number): void {
    this.onIdleFrame();
  }
}

@Component
struct QueueListLifecycleSentinel {
  onRemoved: () => void = (): void => {};

  aboutToDisappear(): void {
    this.onRemoved();
  }

  build() {
    Stack()
      .width(0)
      .height(0)
  }
}

@Component
struct QueueRowDivider {
  @ObjectLink projection: QueueProjectionState;
  @Prop entryId: number = -1;
  @Prop color: ResourceColor = Color.Transparent;

  build() {
    Divider()
      .strokeWidth(PlayerLayoutSpec.FULL_PLAYER_QUEUE_DIVIDER_HEIGHT)
      .color(this.color)
      .opacity(this.projection.displayIndex(this.entryId) > 0 ?
        PlayerLayoutSpec.FULL_PLAYER_QUEUE_DIVIDER_OPACITY : 0)
      .margin({
        left: PlayerLayoutSpec.FULL_PLAYER_QUEUE_INDEX_WIDTH +
          PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE + 20 +
          PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
        right: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET
      })
  }
}

@Component
struct ActiveQueueRowBackground {
  @ObjectLink projection: QueueProjectionState;
  @Prop entryId: number = -1;
  @Prop paneCount: number = 1;

  build() {
    if (this.projection.isActive(this.entryId)) {
      if (this.paneCount > 1) {
        Row()
          .width('100%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Right,
            colors: [
              [$r('app.color.glass_surface_strong'), 0],
              [
                $r('app.color.glass_surface_strong'),
                PlayerLayoutSpec.FULL_PLAYER_QUEUE_ACTIVE_FADE_START
              ],
              [Color.Transparent, 1]
            ]
          })
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.glass_surface_strong'))
      }
    }
  }
}

export function queueTrackListItem(track: QueueTrack): TrackListItem {
  return {
    id: track.id,
    title: track.title,
    artistDisplay: track.artistDisplay,
    albumDisplay: track.albumDisplay,
    durationMs: track.durationMs,
    trackNumber: 0,
    discNumber: 0,
    smallArtworkHash: track.smallArtworkHash,
    smallArtworkPath: track.smallArtworkPath,
    artworkHash: track.largeArtworkHash,
    artworkPath: track.largeArtworkPath,
    artworkWidth: track.artworkWidth,
    artworkHeight: track.artworkHeight,
    palettePrimary: track.palettePrimary,
    paletteSecondary: track.paletteSecondary,
    paletteAccent: track.paletteAccent,
    sectionKey: '',
    availability: AvailabilityState.AVAILABLE
  };
}

@Observed
export class FullPlayerQueueSelectionStore {
  selectedEntries: Array<QueueEntry> = [];
  pendingEntryIds: Array<number> = [];
  pendingSelected: boolean = true;
  selectionActive: boolean = false;

  isSelected(entryId: number): boolean {
    return this.selectedEntries.some((entry: QueueEntry): boolean =>
      entry.queueEntryId === entryId);
  }

  isPresentedSelected(entryId: number): boolean {
    return this.pendingEntryIds.includes(entryId) ? this.pendingSelected : this.isSelected(entryId);
  }

  previewSelection(entryIds: Array<number>, selected: boolean): void {
    this.pendingEntryIds = this.selectionActive ? entryIds.slice() : [];
    this.pendingSelected = selected;
  }

  begin(): void {
    this.selectionActive = true;
    this.selectedEntries = [];
    this.pendingEntryIds = [];
  }

  toggle(entry: QueueEntry): void {
    if (this.isSelected(entry.queueEntryId)) {
      this.selectedEntries = this.selectedEntries.filter((selected: QueueEntry): boolean =>
        selected.queueEntryId !== entry.queueEntryId);
      return;
    }
    this.selectedEntries = this.selectedEntries.concat([entry]);
  }

  setSelected(entry: QueueEntry, selected: boolean): void {
    if (!this.selectionActive || this.isSelected(entry.queueEntryId) === selected) {
      return;
    }
    if (selected) {
      this.selectedEntries = this.selectedEntries.concat([entry]);
    } else {
      this.selectedEntries = this.selectedEntries.filter((item: QueueEntry): boolean =>
        item.queueEntryId !== entry.queueEntryId);
    }
  }

  cancel(): void {
    this.selectionActive = false;
    this.selectedEntries = [];
    this.pendingEntryIds = [];
  }

  toggleAll(entries: Array<QueueEntry>): void {
    const allSelected = entries.length > 0 && this.selectedEntries.length === entries.length &&
      entries.every((entry: QueueEntry): boolean => this.isSelected(entry.queueEntryId));
    this.selectedEntries = allSelected ?
      [] : entries.slice();
  }
}

@Component
struct QueuePositionSlotHost {
  @ObjectLink slot: QueuePositionSlot;
  @ObjectLink projection: QueueProjectionState;
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink selectionStore: FullPlayerQueueSelectionStore;
  @Prop paneCount: number = 1;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop secondaryContentColor: string = '#B8FFFFFF';
  onPlayQueueEntry: (queueEntryId: number) => void = (_queueEntryId: number): void => {};
  onResolveQueueArtwork: (relativePath: string) => string = (_relativePath: string): string => '';
  onOpenTrackDetails: (track: TrackListItem) => void = (_track: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};
  onSelectionTargetAreaChange: (targetKey: number, entry: QueueEntry, area: Area) => void =
    (_targetKey: number, _entry: QueueEntry, _area: Area): void => {};
  onSelectionTargetRemoved: (targetKey: number) => void = (_targetKey: number): void => {};
  onSelectionDragStart: (entryId: number) => void = (_entryId: number): void => {};
  onSelectionDragUpdate: (x: number, y: number) => void = (_x: number, _y: number): void => {};
  onSelectionDragEnd: () => void = (): void => {};
  onSelectionDragCancel: () => void = (): void => {};

  private entry(): QueueEntry {
    return this.projection.entryAt(this.slot.index) as QueueEntry;
  }

  private track(): TrackListItem {
    return queueTrackListItem(this.entry().track);
  }

  build() {
    Column() {
      QueueRowDivider({
        projection: this.projection,
        entryId: this.entry().queueEntryId,
        color: this.secondaryContentColor
      })
      Stack() {
        ActiveQueueRowBackground({
          projection: this.projection,
          entryId: this.entry().queueEntryId,
          paneCount: this.paneCount
        })
        Row() {
          QueueTrackRow({
            entryId: this.entry().queueEntryId,
            selectionTargetKey: this.slot.index,
            projection: this.projection,
            track: this.track(),
            store: this.libraryStore,
            artworkPath: this.onResolveQueueArtwork(this.entry().track.smallArtworkPath),
            primaryColor: this.primaryContentColor,
            secondaryColor: this.secondaryContentColor,
            tertiaryColor: this.secondaryContentColor,
            horizontalInset: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
            verticalInset: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ROW_VERTICAL_INSET,
            artworkSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE,
            artworkCornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
            queueIndexWidth: PlayerLayoutSpec.FULL_PLAYER_QUEUE_INDEX_WIDTH,
            queueGestureDistance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE,
            menuPlacement: Placement.BottomLeft,
            onNavigateAction: this.onNavigateLibrary,
            onRequestAddToPlaylist: (items: Array<TrackListItem>): void =>
              this.onRequestAddToPlaylist(items.map((item: TrackListItem): number => item.id)),
            onOpenDetails: this.onOpenTrackDetails,
            onShareTrackFile: this.onShareTrackFile,
            selectionMode: this.selectionStore.selectionActive,
            selected: this.selectionStore.isPresentedSelected(this.entry().queueEntryId),
            onActivate: (_track: TrackListItem): void =>
              this.onPlayQueueEntry(this.entry().queueEntryId),
            onToggleSelection: (_track: TrackListItem): void =>
              this.selectionStore.toggle(this.entry()),
            onSelectionTargetAreaChange: (targetKey: number, _entryId: number, area: Area): void =>
              this.onSelectionTargetAreaChange(targetKey, this.entry(), area),
            onSelectionTargetRemoved: this.onSelectionTargetRemoved,
            onSelectionDragStart: (entryId: number, _x: number, _y: number): void =>
              this.onSelectionDragStart(entryId),
            onSelectionDragUpdate: this.onSelectionDragUpdate,
            onSelectionDragEnd: this.onSelectionDragEnd,
            onSelectionDragCancel: this.onSelectionDragCancel
          })
            .reuseId('player_queue_track')
        }
        .width('100%')
        .padding({
          left: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_EDGE_INSET,
          right: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_EDGE_INSET
        })
      }
      .width('100%')
    }
    .width('100%')
  }
}

@Component
export struct FullPlayerQueueHeader {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink selectionStore: FullPlayerQueueSelectionStore;
  @ObjectLink refreshState: FullPlayerQueueRefreshState;
  @Prop pageWidth: number = 0;
  @Prop @Watch('onSelectionEnabledChanged') selectionEnabled: boolean = true;
  @Prop leadingInset: number = 0;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop secondaryContentColor: string = '#B8FFFFFF';
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};

  private onSelectionEnabledChanged(): void {
    if (!this.selectionEnabled) {
      this.selectionStore.cancel();
    }
  }

  aboutToAppear(): void {
    this.onSelectionEnabledChanged();
  }

  private animateSelection(change: () => void): void {
    this.getUIContext().animateTo({
      curve: TitleBarMotionSpec.transitionCurve()
    }, change);
  }

  @Builder
  private SelectionMenu() {
    PlayerQueueSelectionMenu(new PlayerQueueSelectionMenuParams(
      () => {
        playbackRuntime.playQueueSelection(
          this.selectionStore.selectedEntries.map((entry: QueueEntry) => entry.track)
        );
        this.selectionStore.cancel();
      },
      () => playbackRuntime.insertQueueTracks(
        this.selectionStore.selectedEntries.map((entry: QueueEntry) => entry.track)
      ),
      () => playbackRuntime.appendQueueTracks(
        this.selectionStore.selectedEntries.map((entry: QueueEntry) => entry.track)
      ),
      () => this.onRequestAddToPlaylist(
        this.selectionStore.selectedEntries.map((entry: QueueEntry): number => entry.track.id)
      ),
      () => {
        playbackRuntime.removeQueueEntries(
          this.selectionStore.selectedEntries.map(
            (entry: QueueEntry): number => entry.queueEntryId
          )
        );
        this.selectionStore.cancel();
      }
    ))
  }

  build() {
    Row({ space: 0 }) {
      Text('当前播放队列')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryContentColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.selectionStore.selectionActive) {
        Button(this.selectionStore.selectedEntries.length === this.playerStore.queueSize ?
          '清空' : '全选')
          .height(40)
          .fontColor(this.primaryContentColor)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.animateSelection((): void => this.selectionStore.toggleAll(
            this.playerStore.queueDataSource.snapshot()
          )))
        Button(`操作 ${this.selectionStore.selectedEntries.length}`)
          .height(40)
          .enabled(this.selectionStore.selectedEntries.length > 0)
          .fontColor(this.primaryContentColor)
          .backgroundColor(Color.Transparent)
          .bindMenu(this.SelectionMenu(), { placement: Placement.BottomRight })
        Button('取消')
          .height(40)
          .fontColor(this.primaryContentColor)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.animateSelection((): void => this.selectionStore.cancel()))
      } else {
        Text(`${this.playerStore.queueSize} 首`)
          .fontSize(13)
          .fontColor(this.secondaryContentColor)
        PlayerModeButton({
          playerStore: this.playerStore,
          action: PlayerModeAction.SHUFFLE,
          buttonSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE,
          iconSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_ICON_SIZE,
          contentColor: this.primaryContentColor,
          interactionEnabled: this.refreshState.canInteract(),
          onAction: (action: PlayerModeAction): boolean => {
            if (action !== PlayerModeAction.SHUFFLE) {
              return false;
            }
            this.selectionStore.cancel();
            this.refreshState.request();
            return true;
          }
        })
        PlayerModeButton({
          playerStore: this.playerStore,
          action: PlayerModeAction.REPEAT,
          buttonSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE,
          iconSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_ICON_SIZE,
          contentColor: this.primaryContentColor,
          interactionEnabled: this.refreshState.canInteract()
        })
        if (this.selectionEnabled) {
          Button() {
            PlayerSymbolIcon({
              symbol: $r('sys.symbol.checkmark_square_on_square'),
              iconSize: 21,
              contentColor: this.primaryContentColor,
              animateColor: false
            })
          }
          .width(PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE)
          .height(PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE)
          .borderRadius(PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE / 2)
          .backgroundColor(Color.Transparent)
          .enabled(this.refreshState.canInteract())
          .accessibilityText('多选')
          .onClick(() => this.animateSelection((): void => this.selectionStore.begin()))
        }
      }
    }
    .width(this.pageWidth)
    .height(PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE)
    .padding({
      left: this.leadingInset,
      right: PlayerLayoutSpec.FULL_PLAYER_PAGE_HORIZONTAL_INSET
    })
  }
}

@Component
export struct FullPlayerQueuePage {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink selectionStore: FullPlayerQueueSelectionStore;
  @ObjectLink refreshState: FullPlayerQueueRefreshState;
  @Prop pageWidth: number = 0;
  @Prop paneCount: number = 1;
  @Prop bottomInset: number = 0;
  @Prop @Watch('onFocusSyncActiveChanged') focusSyncActive: boolean = false;
  @Prop @Watch('onListenerActiveChanged') listenerActive: boolean = true;
  @Prop pageScrollingEnabled: boolean = true;
  @Prop focusAnimationEnabled: boolean = true;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop secondaryContentColor: string = '#B8FFFFFF';
  @State selectionDragActive: boolean = false;
  onPlayQueueEntry: (queueEntryId: number) => void = (_queueEntryId: number): void => {};
  onResolveQueueArtwork: (relativePath: string) => string =
    (_relativePath: string): string => '';
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};
  private readonly queueScroller: Scroller = new Scroller();
  private readonly dragSelection: DragSelectionController =
    new DragSelectionController(
      (ids: Array<number>, selected: boolean): void =>
        this.selectionStore.previewSelection(ids, selected),
      (active: boolean): void => { this.selectionDragActive = active; }
    );
  private readonly focusState: FullPlayerListFocusState = new FullPlayerListFocusState();
  private lastFocusedQueueIndex: number = -1;
  private listenerRegistered: boolean = false;
  private initialFocusSyncScheduled: boolean = false;
  private queueLayoutReady: boolean = false;
  private rebuildCheckScheduled: boolean = false;
  private rebuildCheckAttempts: number = 0;
  private pageActive: boolean = false;
  private readonly queueIndexListener: QueueIndexListener = (index: number): void => {
    if (!this.listenerActive || !this.refreshState.canInteract() || index < 0 ||
      this.playerStore.queueSize === 0) {
      return;
    }
    this.focusQueueIndex(
      index,
      this.focusState.consumeFollowAnimation(this.focusAnimationEnabled)
    );
  };
  private readonly queueProjectionListener: QueueProjectionListener = (): void => {
    this.dragSelection.remapTargets((entryId: number): number =>
      this.playerStore.queueDataSource.projectionState.displayIndex(entryId));
    this.selectionDragActive = false;
  };

  aboutToAppear(): void {
    this.pageActive = true;
    this.playerStore.queueDataSource.addProjectionListener(this.queueProjectionListener);
    this.onFocusSyncActiveChanged();
    this.syncListenerRegistration();
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.dragSelection.end();
    this.playerStore.queueDataSource.removeProjectionListener(this.queueProjectionListener);
    this.removeListener();
    if (this.refreshState.phase === FullPlayerQueueRefreshPhase.REBUILDING_HIDDEN ||
      this.refreshState.phase === FullPlayerQueueRefreshPhase.REVEALING) {
      this.refreshState.complete(this.refreshState.token);
    }
  }

  private onListenerActiveChanged(): void {
    this.syncListenerRegistration();
  }

  private onFocusSyncActiveChanged(): void {
    if (!this.focusSyncActive) {
      return;
    }
    this.focusState.reset();
    this.lastFocusedQueueIndex = -1;
    this.scheduleInitialFocusSync();
  }

  private syncListenerRegistration(): void {
    if (this.pageActive && this.listenerActive && this.refreshState.canInteract() &&
      !this.listenerRegistered) {
      this.playerStore.addQueueIndexListener(this.queueIndexListener);
      this.listenerRegistered = true;
      this.scheduleInitialFocusSync();
    } else if (!this.listenerActive || !this.refreshState.canInteract()) {
      this.removeListener();
    }
  }

  private removeListener(): void {
    if (!this.listenerRegistered) {
      return;
    }
    this.playerStore.removeQueueIndexListener(this.queueIndexListener);
    this.listenerRegistered = false;
  }

  onDidBuild(): void {
    this.syncListenerRegistration();
    this.scheduleInitialFocusSync();
    if (this.refreshState.phase === FullPlayerQueueRefreshPhase.UNMOUNTING &&
      this.playerStore.queueSize === 0) {
      this.onQueueRemoved();
    }
    if (this.refreshState.phase === FullPlayerQueueRefreshPhase.REBUILDING_HIDDEN) {
      this.scheduleRebuildCheck(this.refreshState.token);
    }
  }

  private scheduleInitialFocusSync(): void {
    if (this.initialFocusSyncScheduled) {
      return;
    }
    this.initialFocusSyncScheduled = true;
    Promise.resolve().then((): void => {
      this.initialFocusSyncScheduled = false;
      this.syncInitialFocus();
    });
  }

  private syncInitialFocus(): void {
    if (!this.refreshState.canInteract()) {
      return;
    }
    const queueIndex = this.playerStore.queueCurrentIndex;
    if (this.focusState.canSynchronizeImmediately(
      this.focusSyncActive,
      queueIndex,
      this.playerStore.queueSize
    )) {
      this.focusQueueIndex(queueIndex, false);
      this.focusState.completeImmediateFocus();
    }
  }

  private focusQueueIndex(index: number, animated: boolean): void {
    this.lastFocusedQueueIndex = index;
    this.queueScroller.scrollToIndex(index, animated, ScrollAlign.START);
  }

  private blockVerticalPlayerGesture(recognizers: Array<GestureRecognizer>): void {
    if (!this.pageScrollingEnabled || !this.refreshState.canInteract()) {
      return;
    }
    recognizers.forEach((recognizer: GestureRecognizer) => {
      if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
        recognizer.preventBegin();
      }
    });
  }

  private onQueueRemoved(): void {
    const token = this.refreshState.token;
    if (this.refreshState.phase !== FullPlayerQueueRefreshPhase.UNMOUNTING) {
      return;
    }
    this.queueLayoutReady = false;
    this.removeListener();
    this.getUIContext().postFrameCallback(new QueueRefreshFrameCallback((): void => {
      if (!this.refreshState.markCommitting(token)) {
        return;
      }
      playbackRuntime.toggleShuffleAndPersistExact().then((): void => {
        if (!this.refreshState.markRebuilding(token)) {
          return;
        }
        if (!this.pageActive) {
          this.refreshState.complete(token);
          return;
        }
        this.rebuildCheckAttempts = 0;
        this.scheduleRebuildCheck(token);
      }).catch((error: Object): void => {
        console.warn(`Unable to refresh shuffled queue: ${error}`);
        if (this.refreshState.markRebuilding(token)) {
          if (!this.pageActive) {
            this.refreshState.complete(token);
            return;
          }
          this.rebuildCheckAttempts = 0;
          this.scheduleRebuildCheck(token);
        }
      });
    }));
  }

  private scheduleRebuildCheck(token: number): void {
    if (this.rebuildCheckScheduled || token !== this.refreshState.token ||
      this.refreshState.phase !== FullPlayerQueueRefreshPhase.REBUILDING_HIDDEN) {
      return;
    }
    this.rebuildCheckScheduled = true;
    this.getUIContext().postFrameCallback(new QueueRefreshFrameCallback((): void => {
      this.rebuildCheckScheduled = false;
      if (token !== this.refreshState.token ||
        this.refreshState.phase !== FullPlayerQueueRefreshPhase.REBUILDING_HIDDEN) {
        return;
      }
      if (!this.pageActive) {
        this.refreshState.complete(token);
        return;
      }
      this.rebuildCheckAttempts += 1;
      if (!this.queueLayoutReady && this.rebuildCheckAttempts < 4) {
        this.scheduleRebuildCheck(token);
        return;
      }
      const currentIndex = this.playerStore.queueCurrentIndex;
      if (currentIndex >= 0 && currentIndex < this.playerStore.queueSize) {
        this.focusQueueIndex(currentIndex, false);
      }
      if (!this.refreshState.markRevealing(token)) {
        return;
      }
      this.getUIContext().postFrameCallback(new QueueRefreshFrameCallback((): void => {
        if (!this.pageActive) {
          this.refreshState.complete(token);
          return;
        }
        if (this.refreshState.complete(token)) {
          this.syncListenerRegistration();
          this.scheduleInitialFocusSync();
        }
      }));
    }));
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.refreshState.showsLoading()) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.primaryContentColor)
        }
        .width(this.pageWidth)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({
          top: PlayerLayoutSpec.FULL_PLAYER_PAGE_TOP_INSET +
            (this.paneCount > 1 ? PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE : 0),
          bottom: this.bottomInset
        })
      } else if (this.refreshState.mountsQueue()) {
        Column() {
          if (this.playerStore.queueSize === 0) {
            Column({ space: 8 }) {
              Text('队列为空')
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.primaryContentColor)
              Text('从音乐库选择歌曲后会显示在这里')
                .fontSize(14)
                .fontColor(this.secondaryContentColor)
            }
            .justifyContent(FlexAlign.Center)
            .layoutWeight(1)
            .width('100%')
            .padding({ bottom: this.bottomInset })
          } else {
            Stack() {
              List({ space: 0, scroller: this.queueScroller }) {
                LazyForEach(this.playerStore.queueDataSource,
                  (slot: QueuePositionSlot) => {
                  ListItem() {
                    QueuePositionSlotHost({
                  slot: slot,
                  projection: this.playerStore.queueDataSource.projectionState,
                  libraryStore: this.libraryStore,
                  selectionStore: this.selectionStore,
                  paneCount: this.paneCount,
                  primaryContentColor: this.primaryContentColor,
                  secondaryContentColor: this.secondaryContentColor,
                  onPlayQueueEntry: this.onPlayQueueEntry,
                  onResolveQueueArtwork: this.onResolveQueueArtwork,
                  onOpenTrackDetails: this.onOpenTrackDetails,
                  onShareTrackFile: this.onShareTrackFile,
                  onNavigateLibrary: this.onNavigateLibrary,
                  onRequestAddToPlaylist: this.onRequestAddToPlaylist,
                  onSelectionTargetAreaChange: (targetKey: number, entry: QueueEntry, area: Area): void =>
                    this.dragSelection.updateTarget(
                      targetKey,
                      entry.queueEntryId,
                      this.playerStore.queueDataSource.projectionState.displayIndex(entry.queueEntryId),
                      area,
                      DragSelectionHitMode.ROW,
                      (): boolean => this.selectionStore.isSelected(entry.queueEntryId),
                      (selected: boolean): void => this.selectionStore.setSelected(entry, selected)
                    ),
                  onSelectionTargetRemoved: (targetKey: number): void =>
                    this.dragSelection.removeTarget(targetKey),
                  onSelectionDragStart: (entryId: number): void =>
                    this.dragSelection.start(entryId),
                  onSelectionDragUpdate: (x: number, y: number): void =>
                    this.dragSelection.update(x, y),
                  onSelectionDragEnd: (): void => this.dragSelection.end(),
                  onSelectionDragCancel: (): void => this.dragSelection.cancel()
                    })
                  }
                  .height(PlayerLayoutSpec.FULL_PLAYER_QUEUE_ITEM_HEIGHT)
                }, (slot: QueuePositionSlot) => `queue-slot:${slot.index}`)
              }
              .width('100%')
              .height('100%')
              .edgeEffect(EdgeEffect.Spring)
              .enableScrollInteraction(this.pageScrollingEnabled &&
                this.refreshState.canInteract() && !this.selectionDragActive)
              .cachedCount(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT, true)
              .scrollBar(BarState.Auto)
              .contentEndOffset(this.bottomInset)
              .visibility(this.refreshState.queueVisible() ? Visibility.Visible : Visibility.Hidden)
              .onAreaChange((_oldValue: Area, _newValue: Area): void => {
                this.queueLayoutReady = true;
                this.focusState.markLayoutReady();
                if (this.refreshState.canInteract()) {
                  this.syncInitialFocus();
                } else {
                  this.scheduleRebuildCheck(this.refreshState.token);
                }
              })
              .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) =>
                this.blockVerticalPlayerGesture(recognizers))
              QueueListLifecycleSentinel({ onRemoved: (): void => this.onQueueRemoved() })
            }
            .layoutWeight(1)
            .width('100%')
          }
        }
        .width(this.pageWidth)
        .height('100%')
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) =>
          this.blockVerticalPlayerGesture(recognizers))
        .padding({
          top: PlayerLayoutSpec.FULL_PLAYER_PAGE_TOP_INSET +
            (this.paneCount > 1 ? PlayerLayoutSpec.FULL_PLAYER_CLOSE_BUTTON_SIZE : 0)
        })
      }
    }
    .width(this.pageWidth)
    .height('100%')
  }
}
