import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore, RepeatMode } from '../../playback/model/PlaybackModels';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';

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
      SymbolGlyph(this.playerStore.showsPauseControl() ?
        $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
        .fontSize(this.buttonSize * 0.42)
        .fontColor([this.playerStore.themeOnSecondary()])
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
    .backgroundColor(this.playerStore.themeSecondary())
    .shadow({ radius: 12, color: this.playerStore.themeSecondary(), offsetY: 5 })
    .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .accessibilityText(this.playerStore.showsPauseControl() ? '暂停' : '播放')
    .onClick(() => {
      playbackRuntime.togglePlayback();
    })
  }
}

@Component
export struct PlayerTransportButton {
  @ObjectLink playerStore: PlayerStore;
  @Prop action: PlayerTransportAction = PlayerTransportAction.NEXT;
  @Prop buttonSize: number = 54;
  @Prop contentColor: string = '';

  private icon(): Resource {
    return this.action === PlayerTransportAction.PREVIOUS ?
      $r('app.media.control_previous') : $r('app.media.control_next');
  }

  private accessibilityLabel(): string {
    return this.action === PlayerTransportAction.PREVIOUS ? '上一首' : '下一首';
  }

  private iconColor(): string {
    return this.contentColor.length > 0 ? this.contentColor : this.playerStore.themeOnPrimary();
  }

  build() {
    Stack() {
      Image(this.icon())
        .width(this.buttonSize * 0.45)
        .height(this.buttonSize * 0.45)
        .fillColor(this.iconColor())
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
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
  @Prop buttonSize: number = 44;

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

  private modeForegroundColor(): string {
    if (!this.active()) {
      return this.playerStore.themeOnPrimary();
    }
    const primary = this.playerStore.themePrimary();
    return primary.length > 0 ? primary : this.playerStore.themeBaseBackground;
  }

  build() {
    Stack() {
      SymbolGlyph(this.symbol())
        .fontSize(this.buttonSize * 0.5)
        .fontColor([this.modeForegroundColor()])
        .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })

      if (!this.active()) {
        Row()
          .width(this.buttonSize * 0.57)
          .height(2)
          .borderRadius(1)
          .backgroundColor(this.modeForegroundColor())
          .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
          .rotate({ angle: -45 })
      }
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
    .backgroundColor(this.active() ?
      this.playerStore.themeOnPrimary() : $r('app.color.glass_surface_subtle'))
    .animation({ duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION, curve: Curve.EaseInOut })
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
