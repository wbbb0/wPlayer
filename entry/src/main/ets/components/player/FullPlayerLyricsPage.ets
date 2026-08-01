import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { TimedLyricLine } from '../../playback/lyrics/LyricsParser';
import {
  LyricIndexListener,
  PlayerStore
} from '../../playback/model/PlaybackModels';
import { LibraryPagingPolicy } from '../../library/store/LibraryPagingPolicy';
import { TimedLyricRow } from './FullPlayerSharedControls';
import {
  FULL_PLAYER_VERTICAL_GESTURE_HOST_ID,
  FullPlayerListFocusState,
  PlayerLayoutSpec,
  PlayerMotionSpec
} from './PlayerMotion';

@Component
export struct FullPlayerLyricsPage {
  @ObjectLink playerStore: PlayerStore;
  @Prop pageWidth: number = 0;
  @Prop paneCount: number = 1;
  @Prop rootHeight: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop @Watch('onFocusSyncActiveChanged') focusSyncActive: boolean = false;
  @Prop @Watch('onListenerActiveChanged') listenerActive: boolean = true;
  @Prop pageScrollingEnabled: boolean = true;
  @Prop focusAnimationEnabled: boolean = true;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop secondaryContentColor: string = '#B8FFFFFF';
  onSeek: (positionMs: number) => void = (_positionMs: number): void => {};
  @State private lyricBlurEnabled: boolean = true;
  private readonly lyricScroller: Scroller = new Scroller();
  private readonly focusState: FullPlayerListFocusState = new FullPlayerListFocusState();
  private lastFocusedLyricIndex: number = -1;
  private observedLyricDocumentRevision: number = -1;
  private listenerRegistered: boolean = false;
  private initialFocusSyncScheduled: boolean = false;
  private readonly lyricIndexListener: LyricIndexListener = (index: number): void => {
    this.syncLyricDocument();
    if (!this.listenerActive || index < 0 || this.playerStore.timedLyrics.length === 0) {
      return;
    }
    this.focusLyricIndex(
      index,
      this.focusState.consumeFollowAnimation(this.focusAnimationEnabled)
    );
  };

  aboutToAppear(): void {
    this.syncLyricDocument();
    this.onFocusSyncActiveChanged();
    this.syncListenerRegistration();
  }

  aboutToDisappear(): void {
    this.removeListener();
  }

  private onListenerActiveChanged(): void {
    this.syncListenerRegistration();
  }

  private onFocusSyncActiveChanged(): void {
    if (!this.focusSyncActive) {
      return;
    }
    this.lyricBlurEnabled = true;
    this.focusState.reset();
    this.lastFocusedLyricIndex = -1;
    this.scheduleInitialFocusSync();
  }

  private syncLyricDocument(): void {
    const currentRevision = this.playerStore.lyricDocumentRevision;
    if (currentRevision === this.observedLyricDocumentRevision) {
      return;
    }
    this.observedLyricDocumentRevision = currentRevision;
    this.lyricBlurEnabled = true;
    this.lastFocusedLyricIndex = -1;
    this.focusState.reset();
  }

  private syncListenerRegistration(): void {
    if (this.listenerActive && !this.listenerRegistered) {
      this.lyricBlurEnabled = true;
      this.playerStore.addLyricIndexListener(this.lyricIndexListener);
      this.listenerRegistered = true;
      this.scheduleInitialFocusSync();
    } else if (!this.listenerActive) {
      this.removeListener();
    }
  }

  private removeListener(): void {
    if (!this.listenerRegistered) {
      return;
    }
    this.playerStore.removeLyricIndexListener(this.lyricIndexListener);
    this.listenerRegistered = false;
  }

  onDidBuild(): void {
    this.syncLyricDocument();
    this.scheduleInitialFocusSync();
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
    const lyricIndex = this.playerStore.activeLyricIndex;
    if (this.playerStore.timedLyrics.length === 0) {
      this.lastFocusedLyricIndex = -1;
    }
    if (this.focusState.canSynchronizeImmediately(
      this.focusSyncActive,
      lyricIndex,
      this.playerStore.timedLyrics.length
    )) {
      this.focusLyricIndex(lyricIndex, false);
      this.focusState.completeImmediateFocus();
    }
  }

  private focusLyricIndex(index: number, animated: boolean): void {
    this.lyricBlurEnabled = true;
    this.lastFocusedLyricIndex = index;
    this.lyricScroller.scrollToIndex(Math.max(0, index - 2), animated, ScrollAlign.START);
  }

  private seekToLyric(line: TimedLyricLine): void {
    if (!this.pageScrollingEnabled) {
      return;
    }
    this.lyricBlurEnabled = true;
    this.onSeek(line.timeMs);
  }

  private lyricContentEndOffset(): number {
    const focusTail = Math.max(
      0,
      (this.rootHeight - this.topInset - this.bottomInset) * 0.62
    );
    return focusTail + this.bottomInset;
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

  build() {
    Column() {
      if (this.playerStore.timedLyrics.length > 0) {
        List({ space: PlayerLayoutSpec.FULL_PLAYER_LYRIC_LIST_SPACE, scroller: this.lyricScroller }) {
          LazyForEach(this.playerStore.lyricDataSource, (line: TimedLyricLine, index: number) => {
            ListItem() {
              TimedLyricRow({
                playerStore: this.playerStore,
                line: line,
                index: index,
                blurEnabled: this.lyricBlurEnabled,
                primaryContentColor: this.primaryContentColor,
                secondaryContentColor: this.secondaryContentColor
              })
                .reuseId('timed_lyric')
            }
            .gesture(
              GestureGroup(GestureMode.Exclusive,
                PanGesture({
                  direction: PanDirection.Horizontal,
                  distance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE
                }),
                TapGesture().onAction(() => this.seekToLyric(line))
              )
            )
          }, (line: TimedLyricLine, index: number) => `${line.timeMs}_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .enableScrollInteraction(this.pageScrollingEnabled)
        .cachedCount(LibraryPagingPolicy.TRACK_UI_CACHE_COUNT, true)
        .scrollBar(BarState.Off)
        .contentEndOffset(this.lyricContentEndOffset())
        .onAreaChange((_oldValue: Area, _newValue: Area): void => {
          this.focusState.markLayoutReady();
          this.syncInitialFocus();
        })
        .onWillStartDragging(() => {
          this.lyricBlurEnabled = false;
        })
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) =>
          this.blockVerticalPlayerGesture(recognizers))
      } else if (this.playerStore.lyrics.length > 0) {
        Scroll() {
          Text(this.playerStore.lyrics)
            .width('100%')
            .padding({ bottom: this.bottomInset })
            .fontSize(20)
            .lineHeight(34)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryContentColor)
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .enableScrollInteraction(this.pageScrollingEnabled)
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) =>
          this.blockVerticalPlayerGesture(recognizers))
      } else {
        Column({ space: 10 }) {
          Text('暂未找到内嵌歌词')
            .fontSize(22)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryContentColor)
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          Text('当前仅读取音乐文件内部的歌词文本')
            .fontSize(14)
            .fontColor(this.secondaryContentColor)
            .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
            .textAlign(TextAlign.Center)
        }
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)
        .width('100%')
        .padding({ bottom: this.bottomInset })
      }
    }
    .width(this.pageWidth)
    .height('100%')
    .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) => {
      if (this.playerStore.timedLyrics.length > 0 || this.playerStore.lyrics.length > 0) {
        this.blockVerticalPlayerGesture(recognizers);
      }
    })
    .padding({
      left: PlayerLayoutSpec.FULL_PLAYER_LYRICS_CONTAINER_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.FULL_PLAYER_LYRICS_CONTAINER_HORIZONTAL_INSET,
      top: this.paneCount > 1 ? 0 : PlayerLayoutSpec.FULL_PLAYER_PAGE_TOP_INSET
    })
  }
}
