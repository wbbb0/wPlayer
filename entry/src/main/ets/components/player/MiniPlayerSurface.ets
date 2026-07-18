import { PlayerMotionSpec } from './PlayerMotion';
import { MiniPlayerBinding } from './MiniPlayerBinding';
import { PlayerMiniArtwork } from './PlayerArtworkViews';
import { PlayerPlaybackButton } from './PlayerControls';
import { PlayerMarqueeMotionStore, PlayerTrackMarquee } from './PlayerTrackMarquee';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { LayoutLength } from '../layout/LayoutLength';

export class MiniPlayerHostParams {
  playerStore: PlayerStore;
  marqueeMotionStore: PlayerMarqueeMotionStore;
  binding: MiniPlayerBinding;
  onShowFullPlayer: () => void;
  onGestureStart: () => void;
  onGestureUpdate: (event: GestureEvent) => void;
  onGestureFinish: () => void;

  constructor(playerStore: PlayerStore, marqueeMotionStore: PlayerMarqueeMotionStore,
    binding: MiniPlayerBinding, onShowFullPlayer: () => void,
    onGestureStart: () => void, onGestureUpdate: (event: GestureEvent) => void,
    onGestureFinish: () => void) {
    this.playerStore = playerStore;
    this.marqueeMotionStore = marqueeMotionStore;
    this.binding = binding;
    this.onShowFullPlayer = onShowFullPlayer;
    this.onGestureStart = onGestureStart;
    this.onGestureUpdate = onGestureUpdate;
    this.onGestureFinish = onGestureFinish;
  }
}

@Builder
export function MiniPlayerHost(params: MiniPlayerHostParams) {
  MiniPlayerSurface({
    playerStore: params.playerStore,
    marqueeMotionStore: params.marqueeMotionStore,
    binding: params.binding,
    onShowFullPlayer: params.onShowFullPlayer,
    onGestureStart: params.onGestureStart,
    onGestureUpdate: params.onGestureUpdate,
    onGestureFinish: params.onGestureFinish
  })
}

@Component
export struct MiniPlayerContent {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink marqueeMotionStore: PlayerMarqueeMotionStore;
  @ObjectLink binding: MiniPlayerBinding;
  @Prop showArtwork: boolean = true;
  @Prop followsSwipeOffset: boolean = true;
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

      if (this.binding.expanded) {
        Column({ space: 2 }) {
          PlayerTrackMarquee({
            motionStore: this.marqueeMotionStore,
            playerStore: this.playerStore,
            trackId: this.playerStore.currentTrack?.id ?? -1,
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
        .translate({ x: this.followsSwipeOffset ? this.binding.offsetX : 0 })
        .onClick(() => {
          this.onShowFullPlayer();
        })

        PlayerPlaybackButton({ playerStore: this.playerStore, buttonSize: 40 })
      }
    }
    .height(56)
    .width('100%')
    .padding({ left: 4, right: this.binding.expanded ? 8 : 4 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(28)
    .clip(true)
  }
}

@Component
export struct MiniPlayerSurface {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink marqueeMotionStore: PlayerMarqueeMotionStore;
  @ObjectLink binding: MiniPlayerBinding;
  onShowFullPlayer: () => void = (): void => {};
  onGestureStart: () => void = (): void => {};
  onGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent): void => {};
  onGestureFinish: () => void = (): void => {};

  build() {
    Stack() {
      MiniPlayerContent({
        playerStore: this.playerStore,
        marqueeMotionStore: this.marqueeMotionStore,
        binding: this.binding,
        showArtwork: true,
        followsSwipeOffset: true,
        onShowFullPlayer: this.onShowFullPlayer
      })
    }
    .height(56)
    .width('100%')
    .id('mini_player_surface')
    .borderRadius(28)
    .clip(true)
    .onClick(() => {
      if (!this.binding.expanded) {
        this.onShowFullPlayer();
      }
    })
    .opacity(this.binding.sourceVisible ? 1 : 0)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.binding.measuredFrame = {
        x: LayoutLength.toNumber(newValue.globalPosition.x, this.binding.measuredFrame.x),
        y: LayoutLength.toNumber(newValue.globalPosition.y, this.binding.measuredFrame.y),
        width: LayoutLength.toNumber(newValue.width, this.binding.measuredFrame.width),
        height: LayoutLength.toNumber(newValue.height, this.binding.measuredFrame.height)
      };
    })
    .parallelGesture(
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
        })
    )
  }
}
