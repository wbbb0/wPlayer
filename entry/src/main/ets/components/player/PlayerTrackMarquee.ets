import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { LayoutLength } from '../layout/LayoutLength';

export class PlayerMarqueeMotionSpec {
  static readonly CONTENT_GAP: number = 28;
  static readonly START_DELAY: number = 1200;
  static readonly CYCLE_DURATION: number = 9000;
}

@Observed
export class PlayerMarqueeMotionStore {
  progress: number = 0;
  private trackId: number = Number.MIN_SAFE_INTEGER;
  private trackChangeListener?: (trackId: number) => void;

  bindTrackChangeListener(listener?: (trackId: number) => void): void {
    this.trackChangeListener = listener;
  }

  requestTrack(trackId: number): void {
    if (this.trackId === trackId) {
      return;
    }
    this.trackId = trackId;
    this.trackChangeListener?.(trackId);
  }
}

@Component
export struct PlayerTrackMarquee {
  @ObjectLink motionStore: PlayerMarqueeMotionStore;
  @Prop @Watch('handleTrackChange') trackId: number = -1;
  @Prop title: string = '';
  @Prop titleColor: ResourceColor = '#FFFFFFFF';
  @Prop titleSize: number = 15;
  @Prop titleWeight: FontWeight = FontWeight.Medium;
  @Prop animateColor: boolean = false;
  @State private viewportWidth: number = 0;

  aboutToAppear(): void {
    this.motionStore.requestTrack(this.trackId);
  }

  private handleTrackChange(): void {
    this.motionStore.requestTrack(this.trackId);
  }

  private measuredTextWidth(): number {
    const widthPx = this.getUIContext().getMeasureUtils().measureText({
      textContent: this.title,
      fontSize: this.titleSize,
      fontWeight: this.titleWeight
    });
    return this.getUIContext().px2vp(widthPx);
  }

  private shouldScroll(): boolean {
    return this.viewportWidth > 0 && this.measuredTextWidth() > this.viewportWidth;
  }

  @Builder
  private TitleText() {
    Text(this.title)
      .width(this.measuredTextWidth())
      .fontSize(this.titleSize)
      .fontWeight(this.titleWeight)
      .fontColor(this.titleColor)
      .animation(this.animateColor ? {
        duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
        curve: Curve.EaseInOut
      } : { duration: 0 })
      .maxLines(1)
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.shouldScroll()) {
        Row({ space: PlayerMarqueeMotionSpec.CONTENT_GAP }) {
          this.TitleText()
          this.TitleText()
        }
        .translate({
          x: -this.motionStore.progress *
            (this.measuredTextWidth() + PlayerMarqueeMotionSpec.CONTENT_GAP)
        })
      } else {
        this.TitleText()
      }
    }
    .width('100%')
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.viewportWidth = LayoutLength.toNumber(newValue.width, this.viewportWidth);
    })
  }
}
