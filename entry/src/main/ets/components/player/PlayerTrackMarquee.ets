import { LengthMetrics } from '@kit.ArkUI';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { PlayerStore } from '../../playback/model/PlaybackModels';

class PlayerMarqueeMotionSpec {
  static readonly CONTENT_GAP: number = 28;
  static readonly START_DELAY: number = 1200;
  static readonly STEP: number = 4;
}

@Component
export struct PlayerTrackMarquee {
  @ObjectLink playerStore: PlayerStore;
  @Prop active: boolean = true;
  @Prop titleColor: ResourceColor = '#FFFFFFFF';
  @Prop titleSize: number = 15;
  @Prop titleWeight: FontWeight = FontWeight.Medium;
  @Prop animateColor: boolean = false;

  private currentTitle(): string {
    return this.playerStore.currentTrack?.title ?? '尚未播放';
  }

  @Builder
  private StaticTitle() {
    Text(this.currentTitle())
      .width('100%')
      .fontSize(this.titleSize)
      .fontWeight(this.titleWeight)
      .fontColor(this.titleColor)
      .animation(this.animateColor ? {
        duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
        curve: Curve.EaseInOut
      } : { duration: 0 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Clip })
  }

  @Builder
  private ScrollingTitle() {
    Text(this.currentTitle())
      .width('100%')
      .fontSize(this.titleSize)
      .fontWeight(this.titleWeight)
      .fontColor(this.titleColor)
      .animation(this.animateColor ? {
        duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
        curve: Curve.EaseInOut
      } : { duration: 0 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.MARQUEE })
      .marqueeOptions({
        start: true,
        step: PlayerMarqueeMotionSpec.STEP,
        spacing: LengthMetrics.vp(PlayerMarqueeMotionSpec.CONTENT_GAP),
        loop: -1,
        fromStart: true,
        delay: PlayerMarqueeMotionSpec.START_DELAY,
        fadeout: false,
        marqueeStartPolicy: MarqueeStartPolicy.DEFAULT,
        marqueeUpdatePolicy: MarqueeUpdatePolicy.DEFAULT
      })
  }

  build() {
    if (this.active) {
      this.ScrollingTitle()
    } else {
      this.StaticTitle()
    }
  }
}
