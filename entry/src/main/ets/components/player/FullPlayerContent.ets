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

  private artworkSlotSize(): number {
    return PlayerLayoutSpec.fullArtworkSize(
      this.rootFrame.width,
      this.rootFrame.height,
      this.topInset,
      this.bottomInset
    );
  }

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

      }
      .width('100%')

      Blank().layoutWeight(1)

      Stack() {
        if (this.showArtwork) {
          PlayerHeroArtwork({
            playerStore: this.playerStore,
            slotSize: this.artworkSlotSize(),
            cornerRadius: PlayerLayoutSpec.FULL_ARTWORK_RADIUS
          })
        }
      }
      .width(this.artworkSlotSize())
      .height(this.artworkSlotSize())
      .borderRadius(this.artworkSlotSize() / 2)
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

      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Text(this.playerStore.currentTrack?.title ?? '尚未播放')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .layoutWeight(1)

          Row({ space: 2 }) {
            PlayerModeButton({ playerStore: this.playerStore, action: PlayerModeAction.SHUFFLE })
            PlayerModeButton({ playerStore: this.playerStore, action: PlayerModeAction.REPEAT })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.playerStore.currentTrack?.artistDisplay || '选择一首音乐开始播放')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Row({ space: 16 }) {
        PlayerTransportButton({ action: PlayerTransportAction.PREVIOUS, buttonSize: 52 })
        PlayerPlaybackButton({ playerStore: this.playerStore, buttonSize: 64 })
        PlayerTransportButton({ action: PlayerTransportAction.NEXT, buttonSize: 52 })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .margin({ top: 18, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: PlayerLayoutSpec.FULL_PLAYER_HORIZONTAL_INSET,
      right: PlayerLayoutSpec.FULL_PLAYER_HORIZONTAL_INSET,
      top: this.topInset + 18,
      bottom: this.bottomInset + 10
    })
  }
}
