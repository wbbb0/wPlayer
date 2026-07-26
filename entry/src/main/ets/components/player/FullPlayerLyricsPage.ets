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
  PlayerLayoutSpec
} from './PlayerMotion';

@Component
export struct FullPlayerLyricsPage {
  @ObjectLink playerStore: PlayerStore;
  @Prop pageWidth: number = 0;
  @Prop paneCount: number = 1;
  @Prop rootHeight: number = 0;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop @Watch('onListenerActiveChanged') listenerActive: boolean = true;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop secondaryContentColor: string = '#B8FFFFFF';
  private readonly lyricScroller: Scroller = new Scroller();
  private lastFocusedLyricIndex: number = -1;
  private listenerRegistered: boolean = false;
  private readonly lyricIndexListener: LyricIndexListener = (index: number): void => {
    if (!this.listenerActive || index < 0 || this.playerStore.timedLyrics.length === 0) {
      return;
    }
    this.lastFocusedLyricIndex = index;
    this.lyricScroller.scrollToIndex(Math.max(0, index - 2), true, ScrollAlign.START);
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
      this.playerStore.addLyricIndexListener(this.lyricIndexListener);
      this.listenerRegistered = true;
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
    if (!this.listenerActive) {
      return;
    }
    const lyricIndex = this.playerStore.activeLyricIndex;
    if (this.playerStore.timedLyrics.length === 0) {
      this.lastFocusedLyricIndex = -1;
    }
    if (lyricIndex >= 0 && lyricIndex !== this.lastFocusedLyricIndex) {
      this.lyricIndexListener(lyricIndex);
    }
  }

  private lyricEndOffset(): number {
    return Math.max(0, (this.rootHeight - this.topInset - this.bottomInset) * 0.62);
  }

  private blockVerticalPlayerGesture(recognizers: Array<GestureRecognizer>): void {
    recognizers.forEach((recognizer: GestureRecognizer) => {
      if (recognizer.getEventTargetInfo().getId() === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
        recognizer.preventBegin();
      }
    });
  }

  build() {
    Column() {
      if (this.playerStore.timedLyrics.length > 0) {
        List({ space: 14, scroller: this.lyricScroller }) {
          LazyForEach(this.playerStore.lyricDataSource, (line: TimedLyricLine, index: number) => {
            ListItem() {
              TimedLyricRow({
                playerStore: this.playerStore,
                line: line,
                index: index,
                primaryContentColor: this.primaryContentColor,
                secondaryContentColor: this.secondaryContentColor
              })
                .reuseId('timed_lyric')
            }
          }, (line: TimedLyricLine, index: number) => `${line.timeMs}_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(LibraryPagingPolicy.TRACK_PAGE_SIZE, true)
        .scrollBar(BarState.Off)
        .contentEndOffset(this.lyricEndOffset())
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) =>
          this.blockVerticalPlayerGesture(recognizers))
      } else if (this.playerStore.lyrics.length > 0) {
        Scroll() {
          Text(this.playerStore.lyrics)
            .width('100%')
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
      left: PlayerLayoutSpec.FULL_PLAYER_LYRICS_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.FULL_PLAYER_LYRICS_HORIZONTAL_INSET,
      top: this.paneCount > 1 ? 0 : PlayerLayoutSpec.FULL_PLAYER_PAGE_TOP_INSET,
      bottom: this.bottomInset + PlayerLayoutSpec.FULL_PLAYER_BOTTOM_INSET
    })
  }
}
