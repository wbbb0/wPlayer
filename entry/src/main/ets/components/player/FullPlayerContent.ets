import { PlayerFrame, PlayerLayoutSpec, PlayerPoint } from './PlayerMotion';
import {
  PlayerModeAction,
  PlayerModeButton,
  PlayerPlaybackButton,
  PlayerTransportAction,
  PlayerTransportButton
} from './PlayerControls';
import { PlayerHeroArtwork } from './PlayerArtworkViews';
import { PlayerStore } from '../../playback/model/PlaybackModels';

function lengthToNumber(value: Length | undefined, fallback: number): number {
  if (typeof value === 'number') {
    return value;
  }
  if (typeof value === 'string') {
    const parsedValue = Number.parseFloat(value);
    return Number.isNaN(parsedValue) ? fallback : parsedValue;
  }
  return fallback;
}

@Component
export struct FullPlayerContent {
  @ObjectLink playerStore: PlayerStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop showArtwork: boolean = true;
  @Prop measuresArtworkTarget: boolean = false;
  @Prop rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @Prop previousArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  onClose: () => void = (): void => {};
  onArtworkTarget: (target: PlayerPoint) => void = (_target: PlayerPoint): void => {};

  build() {
    Column() {
      Row() {
        Stack() {
          Image($r('app.media.control_chevron_down'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_primary'))
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor($r('app.color.glass_surface_strong'))
        .backgroundBlurStyle(BlurStyle.Thin)
        .clickEffect({ level: ClickEffectLevel.MIDDLE })
        .accessibilityText('收起播放器')
        .onClick(() => {
          this.onClose();
        })

        Text('正在播放')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(44)
      }
      .width('100%')

      Blank().layoutWeight(1)

      Stack() {
        if (this.showArtwork) {
          PlayerHeroArtwork({
            playerStore: this.playerStore,
            slotSize: PlayerLayoutSpec.FULL_ARTWORK_SIZE,
            cornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS
          })
        }
      }
      .width(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
      .height(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
      .borderRadius(PlayerLayoutSpec.FULL_ARTWORK_SIZE / 2)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        if (!this.measuresArtworkTarget) {
          return;
        }
        this.onArtworkTarget({
          x: lengthToNumber(
            newValue.globalPosition.x,
            this.previousArtworkTarget.x + this.rootFrame.x
          ) - this.rootFrame.x,
          y: lengthToNumber(
            newValue.globalPosition.y,
            this.previousArtworkTarget.y + this.rootFrame.y
          ) - this.rootFrame.y
        });
      })

      Blank().layoutWeight(1)

      Column({ space: 7 }) {
        Text(this.playerStore.currentTrack?.title ?? '尚未播放')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.playerStore.currentTrack?.artistDisplay || '选择一首音乐开始播放')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Row() {
        PlayerTransportButton({ action: PlayerTransportAction.PREVIOUS, buttonSize: 54 })
        PlayerPlaybackButton({ playerStore: this.playerStore, buttonSize: 74 })
        PlayerTransportButton({ action: PlayerTransportAction.NEXT, buttonSize: 54 })
      }
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .margin({ top: 24 })

      Row() {
        PlayerModeButton({ playerStore: this.playerStore, action: PlayerModeAction.SHUFFLE })
        PlayerModeButton({ playerStore: this.playerStore, action: PlayerModeAction.REPEAT })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .padding({ left: 18, right: 18 })
      .margin({ bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 28, right: 28, top: this.topInset + 18, bottom: this.bottomInset + 10 })
  }
}
