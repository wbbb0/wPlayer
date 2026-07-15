import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore, RepeatMode } from '../../playback/model/PlaybackModels';

export enum PlayerTransportAction {
  PREVIOUS,
  NEXT
}

export enum PlayerModeAction {
  SHUFFLE,
  REPEAT
}

@Component
export struct PlayerPlaybackButton {
  @ObjectLink playerStore: PlayerStore;
  @Prop buttonSize: number = 40;

  build() {
    Stack() {
      SymbolGlyph(this.playerStore.isPlaying() ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
        .fontSize(this.buttonSize * 0.42)
        .fontColor(['#FFFFFF'])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
    .backgroundColor($r('app.color.theme_accent'))
    .shadow({ radius: 12, color: $r('app.color.theme_accent_shadow'), offsetY: 5 })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .accessibilityText(this.playerStore.isPlaying() ? '暂停' : '播放')
    .onClick(() => {
      playbackRuntime.togglePlayback();
    })
  }
}

@Component
export struct PlayerTransportButton {
  @Prop action: PlayerTransportAction = PlayerTransportAction.NEXT;
  @Prop buttonSize: number = 54;

  private icon(): Resource {
    return this.action === PlayerTransportAction.PREVIOUS ?
      $r('app.media.control_previous') : $r('app.media.control_next');
  }

  private accessibilityLabel(): string {
    return this.action === PlayerTransportAction.PREVIOUS ? '上一首' : '下一首';
  }

  build() {
    Stack() {
      Image(this.icon())
        .width(this.buttonSize * 0.45)
        .height(this.buttonSize * 0.45)
        .fillColor($r('app.color.control_foreground'))
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
    .backgroundColor($r('app.color.glass_surface_subtle'))
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .accessibilityText(this.accessibilityLabel())
    .onClick(() => {
      if (this.action === PlayerTransportAction.PREVIOUS) {
        playbackRuntime.previous();
      } else {
        playbackRuntime.next();
      }
    })
  }
}

@Component
export struct PlayerModeButton {
  @ObjectLink playerStore: PlayerStore;
  @Prop action: PlayerModeAction = PlayerModeAction.SHUFFLE;

  private symbol(): Resource {
    if (this.action === PlayerModeAction.SHUFFLE) {
      return $r('sys.symbol.shuffle');
    }
    return this.playerStore.repeatMode === RepeatMode.ONE ?
      $r('sys.symbol.repeat_1') : $r('sys.symbol.repeat');
  }

  private active(): boolean {
    return this.action === PlayerModeAction.SHUFFLE ?
      this.playerStore.shuffleEnabled : this.playerStore.repeatMode !== RepeatMode.OFF;
  }

  private accessibilityLabel(): string {
    if (this.action === PlayerModeAction.SHUFFLE) {
      return this.playerStore.shuffleEnabled ? '关闭随机播放' : '开启随机播放';
    }
    return '切换循环模式';
  }

  build() {
    Stack() {
      SymbolGlyph(this.symbol())
        .fontSize(22)
        .fontColor([this.active() ? $r('app.color.theme_accent') : $r('app.color.text_secondary')])
    }
    .width(44)
    .height(44)
    .borderRadius(22)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .accessibilityText(this.accessibilityLabel())
    .onClick(() => {
      if (this.action === PlayerModeAction.SHUFFLE) {
        playbackRuntime.toggleShuffle();
      } else {
        playbackRuntime.cycleRepeatMode();
      }
    })
  }
}
