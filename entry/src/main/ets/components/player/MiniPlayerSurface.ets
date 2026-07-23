import { MiniPlayerClickSuppressor, PlayerLayoutSpec, PlayerMotionSpec } from './PlayerMotion';
import { MiniPlayerBinding } from './MiniPlayerBinding';
import { PlayerMiniArtwork } from './PlayerArtworkViews';
import { PlayerPlaybackButton } from './PlayerControls';
import { PlayerTrackMarquee } from './PlayerTrackMarquee';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { LayoutLength } from '../layout/LayoutLength';

export class MiniPlayerHostParams {
  playerStore: PlayerStore;
  binding: MiniPlayerBinding;
  onShowFullPlayer: () => void;
  onTouchDown: (localX: number) => void;
  onGestureStart: () => void;
  onGestureUpdate: (event: GestureEvent) => void;
  onGestureFinish: () => void;

  constructor(playerStore: PlayerStore, binding: MiniPlayerBinding, onShowFullPlayer: () => void,
    onTouchDown: (localX: number) => void, onGestureStart: () => void,
    onGestureUpdate: (event: GestureEvent) => void, onGestureFinish: () => void) {
    this.playerStore = playerStore;
    this.binding = binding;
    this.onShowFullPlayer = onShowFullPlayer;
    this.onTouchDown = onTouchDown;
    this.onGestureStart = onGestureStart;
    this.onGestureUpdate = onGestureUpdate;
    this.onGestureFinish = onGestureFinish;
  }
}

@Builder
export function MiniPlayerHost(params: MiniPlayerHostParams) {
  MiniPlayerSurface({
    playerStore: params.playerStore,
    binding: params.binding,
    onShowFullPlayer: params.onShowFullPlayer,
    onTouchDown: params.onTouchDown,
    onGestureStart: params.onGestureStart,
    onGestureUpdate: params.onGestureUpdate,
    onGestureFinish: params.onGestureFinish
  })
}

@Component
export struct MiniPlayerContent {
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink binding: MiniPlayerBinding;
  @Prop showArtwork: boolean = true;
  @Prop showPlaybackButton: boolean = true;
  @Prop followsSwipeOffset: boolean = true;
  @Prop marqueeActive: boolean = true;
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
            playerStore: this.playerStore,
            active: this.marqueeActive,
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

        PlayerPlaybackButton({
          playerStore: this.playerStore,
          buttonSize: PlayerLayoutSpec.MINI_PLAYBACK_BUTTON_SIZE
        })
          .opacity(this.showPlaybackButton ? 1 : 0)
          .enabled(this.showPlaybackButton)
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
  @ObjectLink binding: MiniPlayerBinding;
  private readonly clickSuppressor: MiniPlayerClickSuppressor = new MiniPlayerClickSuppressor();
  onShowFullPlayer: () => void = (): void => {};
  onTouchDown: (localX: number) => void = (_localX: number): void => {};
  onGestureStart: () => void = (): void => {};
  onGestureUpdate: (event: GestureEvent) => void = (_event: GestureEvent): void => {};
  onGestureFinish: () => void = (): void => {};

  build() {
    Stack() {
      MiniPlayerContent({
        playerStore: this.playerStore,
        binding: this.binding,
        showArtwork: true,
        showPlaybackButton: true,
        followsSwipeOffset: true,
        marqueeActive: this.binding.sourceMarqueeActive,
        onShowFullPlayer: (): void => this.requestShowFullPlayer()
      })
    }
    .height(56)
    .width('100%')
    .id('mini_player_surface')
    .borderRadius(28)
    .clip(true)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down && event.touches.length > 0) {
        this.onTouchDown(event.touches[0].x);
      }
      event.stopPropagation();
    })
    .onClick(() => {
      if (!this.binding.expanded) {
        this.requestShowFullPlayer();
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
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE })
        .onActionStart(() => {
          this.clickSuppressor.markPanRecognized();
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

  private requestShowFullPlayer(): void {
    if (this.clickSuppressor.consumeClickSuppression()) {
      return;
    }
    this.onShowFullPlayer();
  }
}
