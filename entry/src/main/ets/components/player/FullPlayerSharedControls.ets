import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { TimedLyricLine } from '../../playback/lyrics/LyricsParser';
import {
  PlaybackProgressStore,
  PlayerStore
} from '../../playback/model/PlaybackModels';
import {
  FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID,
  FULL_PLAYER_VERTICAL_GESTURE_HOST_ID,
  PlayerLayoutSpec,
  PlayerMotionSpec
} from './PlayerMotion';

@Reusable
@Component
export struct TimedLyricRow {
  @ObjectLink playerStore: PlayerStore;
  @Prop line: TimedLyricLine;
  @Prop index: number = -1;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop secondaryContentColor: string = '#B8FFFFFF';

  build() {
    Text(this.line.text)
      .width('100%')
      .fontSize(23)
      .lineHeight(38)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.index === this.playerStore.activeLyricIndex ?
        this.primaryContentColor : this.secondaryContentColor)
      .animation({ duration: PlayerMotionSpec.LYRIC_FOCUS_DURATION, curve: Curve.EaseInOut })
      .opacity(this.index === this.playerStore.activeLyricIndex ? 1 : 0.72)
      .textAlign(TextAlign.Start)
      .scale({
        x: this.index === this.playerStore.activeLyricIndex ? 1 : 0.88,
        y: this.index === this.playerStore.activeLyricIndex ? 1 : 0.88,
        centerX: '0%',
        centerY: '50%'
      })
      .animation({ duration: PlayerMotionSpec.LYRIC_FOCUS_DURATION, curve: Curve.EaseInOut })
  }
}

@Component
export struct PlayerProgressControl {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink progressStore: PlaybackProgressStore;
  @Prop primaryContentColor: string = '#FFFFFFFF';
  @Prop secondaryContentColor: string = '#B8FFFFFF';
  onSeek: (positionMs: number) => void = (_positionMs: number): void => {};
  @State private seeking: boolean = false;
  @State private seekPreviewMs: number = 0;

  private durationLabel(durationMs: number): string {
    const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
  }

  private displayedPositionMs(): number {
    if (this.seeking) {
      return this.seekPreviewMs;
    }
    return Math.max(0, Math.min(this.progressStore.positionMs, this.progressStore.durationMs));
  }

  private updateSeek(value: number, mode: SliderChangeMode): void {
    this.seekPreviewMs = Math.max(0, Math.min(value, this.progressStore.durationMs));
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.seeking = true;
      return;
    }
    this.seeking = false;
    this.onSeek(Math.round(this.seekPreviewMs));
  }

  build() {
    Column({ space: 2 }) {
      Slider({
        value: this.displayedPositionMs(),
        min: 0,
        max: Math.max(1, this.progressStore.durationMs),
        step: 1000,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .selectedColor(this.primaryContentColor)
        .trackColor(this.secondaryContentColor)
        .blockColor(this.primaryContentColor)
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        .trackThickness(PlayerLayoutSpec.FULL_PLAYER_PROGRESS_TRACK_THICKNESS)
        .enabled(this.progressStore.durationMs > 0)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.updateSeek(value, mode);
        })
        .onTouchTestDone((_event: BaseGestureEvent, recognizers: Array<GestureRecognizer>) => {
          recognizers.forEach((recognizer: GestureRecognizer) => {
            const targetId = recognizer.getEventTargetInfo().getId();
            if (targetId === FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID ||
              targetId === FULL_PLAYER_VERTICAL_GESTURE_HOST_ID) {
              recognizer.preventBegin();
            }
          });
        })

      Row() {
        Text(this.durationLabel(this.displayedPositionMs()))
          .fontSize(11)
          .fontColor(this.secondaryContentColor)
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        Blank()
        Text(this.durationLabel(this.progressStore.durationMs))
          .fontSize(11)
          .fontColor(this.secondaryContentColor)
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
      }
      .width('100%')
    }
    .width('100%')
    .margin({ top: 8 })
  }
}
