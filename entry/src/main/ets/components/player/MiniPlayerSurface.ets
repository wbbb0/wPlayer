import { PlayerFrame, PlayerLayoutSpec, PlayerMotionSpec } from './PlayerMotion';
import { PlayerMiniArtwork } from './PlayerArtworkViews';
import { PlayerPlaybackButton } from './PlayerControls';
import { PlayerMarqueeMotionStore, PlayerTrackMarquee } from './PlayerTrackMarquee';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { LayoutLength } from '../layout/LayoutLength';

@Component
export struct MiniPlayerContent {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink marqueeMotionStore: PlayerMarqueeMotionStore;
  @Prop expanded: boolean = false;
  @Prop showArtwork: boolean = true;
  @Prop followsSwipeOffset: boolean = true;
  @Prop swipeOffsetX: number = 0;
  onShowFullPlayer: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      Stack() {
        if (this.showArtwork) {
          PlayerMiniArtwork({ playerStore: this.playerStore })
        }
      }
      .width(48)
      .height(48)
      .zIndex(2)
      .onClick(() => {
        this.onShowFullPlayer();
      })

      if (this.expanded) {
        Column({ space: 2 }) {
          PlayerTrackMarquee({
            motionStore: this.marqueeMotionStore,
            trackId: this.playerStore.currentTrack?.id ?? -1,
            title: this.playerStore.currentTrack?.title ?? '尚未播放',
            titleColor: $r('app.color.text_primary'),
            titleSize: 15,
            titleWeight: FontWeight.Medium
          })

          Text(this.playerStore.currentTrack?.artistDisplay || '选择一首音乐')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .translate({ x: this.followsSwipeOffset ? this.swipeOffsetX : 0 })
        .onClick(() => {
          this.onShowFullPlayer();
        })

        PlayerPlaybackButton({ playerStore: this.playerStore, buttonSize: 40 })
      }
    }
    .height(56)
    .width('100%')
    .padding({ left: 4, right: this.expanded ? 8 : 4 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(28)
    .clip(true)
  }
}

@Component
export struct MiniPlayerSurface {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink marqueeMotionStore: PlayerMarqueeMotionStore;
  @Prop expanded: boolean = false;
  @Prop swipeOffsetX: number = 0;
  @Prop morphActive: boolean = false;
  @Prop measuredFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  onShowFullPlayer: () => void = (): void => {};
  onMeasuredFrame: (frame: PlayerFrame) => void = (_frame: PlayerFrame): void => {};
  onGestureStart: () => void = (): void => {};
  onGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent): void => {};
  onGestureFinish: () => void = (): void => {};

  build() {
    Stack() {
      MiniPlayerContent({
        playerStore: this.playerStore,
        marqueeMotionStore: this.marqueeMotionStore,
        expanded: this.expanded,
        showArtwork: true,
        followsSwipeOffset: true,
        swipeOffsetX: this.swipeOffsetX,
        onShowFullPlayer: this.onShowFullPlayer
      })
    }
    .height(56)
    .width('100%')
    .id('mini_player_surface')
    .borderRadius(28)
    .clip(true)
    .opacity(this.morphActive ? 0 : 1)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.onMeasuredFrame({
        x: LayoutLength.toNumber(newValue.globalPosition.x, this.measuredFrame.x),
        y: LayoutLength.toNumber(newValue.globalPosition.y, this.measuredFrame.y),
        width: LayoutLength.toNumber(newValue.width, this.measuredFrame.width),
        height: LayoutLength.toNumber(newValue.height, this.measuredFrame.height)
      });
    })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE })
        .onActionStart(() => {
          this.onGestureStart();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.onGestureUpdate(event);
        })
        .onActionEnd(() => {
          this.onGestureFinish();
        })
        .onActionCancel(() => {
          this.onGestureFinish();
        }),
      GestureMask.Normal
    )
  }
}
