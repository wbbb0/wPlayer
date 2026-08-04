import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore, RepeatMode } from '../../playback/model/PlaybackModels';
import { PaletteMotionSpec } from '../../appearance/PaletteMotionSpec';
import { DynamicColor, DynamicContainerRole } from '../../appearance/DynamicColor';

export enum PlayerTransportAction {
  PREVIOUS,
  NEXT
}

export enum PlayerModeAction {
  SHUFFLE,
  REPEAT
}

@Component
export struct PlayerSymbolIcon {
  @Prop symbol: Resource;
  @Prop iconSize: number = 20;
  @Prop contentColor: ResourceColor = '#FFFFFFFF';
  @Prop animateColor: boolean = true;

  build() {
    Stack() {
      if (this.animateColor) {
        SymbolGlyph(this.symbol)
          .fontSize(this.iconSize)
          .fontColor([this.contentColor])
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
          .animation({
          duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
          curve: Curve.EaseInOut
          })
      } else {
        SymbolGlyph(this.symbol)
          .fontSize(this.iconSize)
          .fontColor([this.contentColor])
          .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
      }
    }
  }
}

@Component
export struct PlayerImageIcon {
  @Prop source: Resource;
  @Prop iconSize: number = 20;
  @Prop contentColor: ResourceColor = '#FFFFFFFF';
  @Prop animateColor: boolean = true;

  build() {
    Stack() {
      if (this.animateColor) {
        Image(this.source)
          .width(this.iconSize)
          .height(this.iconSize)
          .fillColor(this.contentColor)
          .animation({
          duration: PaletteMotionSpec.COLOR_TRANSITION_DURATION,
          curve: Curve.EaseInOut
          })
      } else {
        Image(this.source)
          .width(this.iconSize)
          .height(this.iconSize)
          .fillColor(this.contentColor)
      }
    }
  }
}

@Component
export struct PlayerPlaybackButton {
  @ObjectLink playerStore: PlayerStore;
  @Prop buttonSize: number = 40;
  @Prop iconSize: number = 0;
  @Prop iconAnimationEnabled: boolean = true;
  @Prop contentColor: string = '';

  private icon(): Resource {
    return this.playerStore.showsPauseControl() ?
      $r('sys.symbol.pause') : $r('sys.symbol.play_fill');
  }

  private iconColor(): string {
    return this.contentColor.length > 0 ? this.contentColor : DynamicColor.foreground(
      this.playerStore.themeBaseBackground,
      DynamicContainerRole.PRIMARY
    );
  }

  private resolvedIconSize(): number {
    return this.iconSize > 0 ? this.iconSize : this.buttonSize * 0.42;
  }

  build() {
    Stack() {
      PlayerSymbolIcon({
        symbol: this.icon(),
        iconSize: this.resolvedIconSize(),
        contentColor: this.iconColor(),
        animateColor: this.iconAnimationEnabled
      })
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
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
  @Prop iconAnimationEnabled: boolean = true;
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
      PlayerImageIcon({
        source: this.icon(),
        iconSize: this.buttonSize * 0.45,
        contentColor: this.iconColor(),
        animateColor: this.iconAnimationEnabled
      })
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
    .backgroundColor(Color.Transparent)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
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
  @Prop iconSize: number = 0;
  @Prop contentColor: string = '#FFFFFFFF';
  @Prop interactionEnabled: boolean = true;
  onAction: (action: PlayerModeAction) => boolean = (_action: PlayerModeAction): boolean => false;

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
    return this.contentColor;
  }

  private resolvedIconSize(): number {
    return this.iconSize > 0 ? this.iconSize : this.buttonSize * 0.5;
  }

  build() {
    Stack() {
      PlayerSymbolIcon({
        symbol: this.symbol(),
        iconSize: this.resolvedIconSize(),
        contentColor: this.modeForegroundColor(),
        animateColor: false
      })

      if (!this.active()) {
        Row()
          .width(this.resolvedIconSize() * 1.14)
          .height(2)
          .borderRadius(1)
          .backgroundColor(this.modeForegroundColor())
          .rotate({ angle: -45 })
      }
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
    .backgroundColor(Color.Transparent)
    .opacity(this.active() ? 1 : 0.72)
    .enabled(this.interactionEnabled)
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .accessibilityText(this.accessibilityLabel())
    .onClick(() => {
      if (this.onAction(this.action)) {
        return;
      }
      if (this.action === PlayerModeAction.SHUFFLE) {
        playbackRuntime.toggleShuffle();
      } else {
        playbackRuntime.cycleRepeatMode();
      }
    })
  }
}
