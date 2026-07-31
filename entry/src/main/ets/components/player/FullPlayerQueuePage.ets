import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { TitleBarMotionSpec } from '../navigation/TitleBarMotionSpec';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import {
  PlayerStore,
  QueueEntry,
  QueueIndexListener,
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
  selectionActive: boolean = false;

  isSelected(entryId: number): boolean {
    return this.selectedEntries.some((entry: QueueEntry): boolean =>
      entry.queueEntryId === entryId);
  }

  begin(): void {
    this.selectionActive = true;
    this.selectedEntries = [];
  }

  toggle(entry: QueueEntry): void {
    if (this.isSelected(entry.queueEntryId)) {
      this.selectedEntries = this.selectedEntries.filter((selected: QueueEntry): boolean =>
        selected.queueEntryId !== entry.queueEntryId);
      return;
    }
    this.selectedEntries = this.selectedEntries.concat([entry]);
  }

  cancel(): void {
    this.selectionActive = false;
    this.selectedEntries = [];
  }

  toggleAll(entries: Array<QueueEntry>): void {
    const allSelected = entries.length > 0 && this.selectedEntries.length === entries.length &&
      entries.every((entry: QueueEntry): boolean => this.isSelected(entry.queueEntryId));
    this.selectedEntries = allSelected ?
      [] : entries.slice();
  }
}

@Component
export struct FullPlayerQueueHeader {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink selectionStore: FullPlayerQueueSelectionStore;
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
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
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
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        PlayerModeButton({
          playerStore: this.playerStore,
          action: PlayerModeAction.SHUFFLE,
          buttonSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE,
          iconSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_ICON_SIZE,
          contentColor: this.primaryContentColor
        })
        PlayerModeButton({
          playerStore: this.playerStore,
          action: PlayerModeAction.REPEAT,
          buttonSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE,
          iconSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_ICON_SIZE,
          contentColor: this.primaryContentColor
        })
        if (this.selectionEnabled) {
          Button() {
            PlayerSymbolIcon({
              symbol: $r('sys.symbol.checkmark_square_on_square'),
              iconSize: 21,
              contentColor: this.primaryContentColor
            })
          }
          .width(PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE)
          .height(PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE)
          .borderRadius(PlayerLayoutSpec.FULL_PLAYER_QUEUE_HEADER_BUTTON_SIZE / 2)
          .backgroundColor(Color.Transparent)
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
  @Prop pageWidth: number = 0;
  @Prop paneCount: number = 1;
  @Prop bottomInset: number = 0;
  @Prop @Watch('onListenerActiveChanged') listenerActive: boolean = true;
  @Prop pageScrollingEnabled: boolean = true;
  @Prop focusAnimationEnabled: boolean = true;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop secondaryContentColor: string = '#B8FFFFFF';
  onPlayQueueTrack: (trackId: number) => void = (_trackId: number): void => {};
  onResolveQueueArtwork: (relativePath: string) => string =
    (_relativePath: string): string => '';
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};
  private readonly queueScroller: Scroller = new Scroller();
  private readonly focusState: FullPlayerListFocusState = new FullPlayerListFocusState();
  private lastFocusedQueueIndex: number = -1;
  private listenerRegistered: boolean = false;
  private readonly queueIndexListener: QueueIndexListener = (index: number): void => {
    if (!this.listenerActive || index < 0 || this.playerStore.queueSize === 0) {
      return;
    }
    this.focusQueueIndex(
      index,
      this.focusState.consumeAnimated(this.focusAnimationEnabled)
    );
  };

  aboutToAppear(): void {
    this.syncListenerRegistration();
  }

  aboutToDisappear(): void {
    this.removeListener();
  }

  private onListenerActiveChanged(): void {
    this.syncListenerRegistration();
  }

  private syncListenerRegistration(): void {
    if (this.listenerActive && !this.listenerRegistered) {
      this.focusState.reset();
      this.playerStore.addQueueIndexListener(this.queueIndexListener);
      this.listenerRegistered = true;
    } else if (!this.listenerActive) {
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
    if (this.listenerActive && this.playerStore.queueCurrentIndex >= 0 &&
      this.lastFocusedQueueIndex !== this.playerStore.queueCurrentIndex) {
      this.focusQueueIndex(
        this.playerStore.queueCurrentIndex,
        this.focusState.consumeAnimated(this.focusAnimationEnabled)
      );
    }
  }

  private focusQueueIndex(index: number, animated: boolean): void {
    this.lastFocusedQueueIndex = index;
    this.queueScroller.scrollToIndex(index, animated, ScrollAlign.START);
  }

  private blockVerticalPlayerGesture(recognizers: Array<GestureRecognizer>): void {
    if (!this.pageScrollingEnabled) {
      return;
    }
    recognizers.forEach((recognizer: GestureRecognizer) => {
      if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
        recognizer.preventBegin();
      }
    });
  }

  @Builder
  private ActiveQueueRowBackground() {
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

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.playerStore.queueSize === 0) {
          Column({ space: 8 }) {
            Text('队列为空')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryContentColor)
              .animation({
                duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
                curve: Curve.EaseInOut
              })
            Text('从音乐库选择歌曲后会显示在这里')
              .fontSize(14)
              .fontColor(this.secondaryContentColor)
              .animation({
                duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
                curve: Curve.EaseInOut
              })
          }
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
          .width('100%')
          .padding({ bottom: this.bottomInset })
        } else {
          List({ space: 0, scroller: this.queueScroller }) {
            LazyForEach(this.playerStore.queueDataSource, (entry: QueueEntry, index: number) => {
              ListItem() {
                Column() {
                  if (index > 0) {
                    Divider()
                      .strokeWidth(PlayerLayoutSpec.FULL_PLAYER_QUEUE_DIVIDER_HEIGHT)
                      .color(this.secondaryContentColor)
                      .opacity(PlayerLayoutSpec.FULL_PLAYER_QUEUE_DIVIDER_OPACITY)
                      .margin({
                        left: PlayerLayoutSpec.FULL_PLAYER_QUEUE_INDEX_WIDTH +
                          PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE + 20 +
                          PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
                        right: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET
                      })
                  }
                  Stack() {
                    if (index === this.playerStore.queueCurrentIndex) {
                      this.ActiveQueueRowBackground()
                    }
                    Row() {
                      QueueTrackRow({
                        track: queueTrackListItem(entry.track),
                        store: this.libraryStore,
                        artworkPath: this.onResolveQueueArtwork(entry.track.smallArtworkPath),
                        queueIndex: index,
                        currentQueueIndex: this.playerStore.queueCurrentIndex,
                        primaryColor: this.primaryContentColor,
                        secondaryColor: this.secondaryContentColor,
                        tertiaryColor: this.secondaryContentColor,
                        animateColors: true,
                        active: entry.track.id === this.playerStore.currentTrack?.id,
                        horizontalInset: PlayerLayoutSpec.FULL_PLAYER_QUEUE_CONTENT_HORIZONTAL_INSET,
                        verticalInset: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ROW_VERTICAL_INSET,
                        artworkSize: PlayerLayoutSpec.FULL_PLAYER_QUEUE_ARTWORK_SIZE,
                        artworkCornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS,
                        queueIndexWidth: PlayerLayoutSpec.FULL_PLAYER_QUEUE_INDEX_WIDTH,
                        queueGestureDistance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE,
                        menuPlacement: Placement.BottomLeft,
                        onNavigateAction: this.onNavigateLibrary,
                        onRequestAddToPlaylist: (items: Array<TrackListItem>): void =>
                          this.onRequestAddToPlaylist(
                            items.map((item: TrackListItem): number => item.id)
                          ),
                        onOpenDetails: this.onOpenTrackDetails,
                        selectionMode: this.selectionStore.selectionActive,
                        selected: this.selectionStore.isSelected(entry.queueEntryId),
                        onActivate: (track: TrackListItem): void =>
                          this.onPlayQueueTrack(track.id),
                        onToggleSelection: (_track: TrackListItem): void =>
                          this.selectionStore.toggle(entry)
                      })
                        .reuseId(this.selectionStore.selectionActive ?
                          'player_queue_selection' : 'player_queue_track')
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
              .height(PlayerLayoutSpec.FULL_PLAYER_QUEUE_ITEM_HEIGHT)
            }, (entry: QueueEntry) => `${entry.queueEntryId}`)
          }
          .layoutWeight(1)
          .width('100%')
          .edgeEffect(EdgeEffect.Spring)
          .enableScrollInteraction(this.pageScrollingEnabled)
          .cachedCount(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT, true)
          .scrollBar(BarState.Auto)
          .contentEndOffset(this.bottomInset)
          .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) =>
            this.blockVerticalPlayerGesture(recognizers))
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
    .width(this.pageWidth)
    .height('100%')
  }
}
