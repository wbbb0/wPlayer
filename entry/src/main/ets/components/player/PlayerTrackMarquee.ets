import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { PlayerStore } from '../../playback/model/PlaybackModels';
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
  private nextConsumerId: number = 0;
  private readonly scrollingConsumers: Set<number> = new Set<number>();
  private trackChangeListener?: (trackId: number) => void;
  private activityChangeListener?: (active: boolean) => void;

  bindTrackChangeListener(listener?: (trackId: number) => void): void {
    this.trackChangeListener = listener;
  }

  bindActivityChangeListener(listener?: (active: boolean) => void): void {
    this.activityChangeListener = listener;
  }

  requestTrack(trackId: number): void {
    if (this.trackId === trackId) {
      return;
    }
    this.trackId = trackId;
    this.trackChangeListener?.(trackId);
  }

  registerConsumer(): number {
    this.nextConsumerId += 1;
    return this.nextConsumerId;
  }

  setConsumerScrolling(consumerId: number, scrolling: boolean): void {
    const wasActive = this.hasScrollingConsumers();
    if (scrolling) {
      this.scrollingConsumers.add(consumerId);
    } else {
      this.scrollingConsumers.delete(consumerId);
    }
    const active = this.hasScrollingConsumers();
    if (active !== wasActive) {
      this.activityChangeListener?.(active);
    }
  }

  unregisterConsumer(consumerId: number): void {
    this.setConsumerScrolling(consumerId, false);
  }

  hasScrollingConsumers(): boolean {
    return this.scrollingConsumers.size > 0;
  }
}

@Component
export struct PlayerTrackMarquee {
  @ObjectLink motionStore: PlayerMarqueeMotionStore;
  @ObjectLink playerStore: PlayerStore;
  @Prop @Watch('handleTrackChange') trackId: number = -1;
  @Prop titleColor: ResourceColor = '#FFFFFFFF';
  @Prop titleSize: number = 15;
  @Prop titleWeight: FontWeight = FontWeight.Medium;
  @Prop animateColor: boolean = false;
  @State private viewportWidth: number = 0;
  @State private textWidth: number = 0;
  private consumerId: number = -1;

  aboutToAppear(): void {
    this.consumerId = this.motionStore.registerConsumer();
    this.refreshTextMetrics();
    this.motionStore.requestTrack(this.trackId);
  }

  aboutToDisappear(): void {
    if (this.consumerId >= 0) {
      this.motionStore.unregisterConsumer(this.consumerId);
      this.consumerId = -1;
    }
  }

  private handleTrackChange(): void {
    this.refreshTextMetrics();
    this.motionStore.requestTrack(this.trackId);
  }

  private refreshTextMetrics(): void {
    const widthPx = this.getUIContext().getMeasureUtils().measureText({
      textContent: this.currentTitle(),
      fontSize: this.titleSize,
      fontWeight: this.titleWeight
    });
    this.textWidth = this.getUIContext().px2vp(widthPx);
    this.updateScrollingState();
  }

  private currentTitle(): string {
    return this.playerStore.currentTrack?.title ?? '尚未播放';
  }

  private shouldScroll(): boolean {
    return this.viewportWidth > 0 && this.textWidth > this.viewportWidth;
  }

  private updateScrollingState(): void {
    if (this.consumerId >= 0) {
      this.motionStore.setConsumerScrolling(this.consumerId, this.shouldScroll());
    }
  }

  @Builder
  private TitleText() {
    Text(this.currentTitle())
      .width(this.textWidth)
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
            (this.textWidth + PlayerMarqueeMotionSpec.CONTENT_GAP)
        })
      } else {
        this.TitleText()
      }
    }
    .width('100%')
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.viewportWidth = LayoutLength.toNumber(newValue.width, this.viewportWidth);
      this.updateScrollingState();
    })
  }
}
