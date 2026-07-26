import { DynamicBackgroundV3NativeContext } from 'libwplayerbackground.so';
import { DynamicColor } from '../../appearance/DynamicColor';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { DynamicBackgroundArtworkCoordinator } from './DynamicBackgroundArtworkCoordinator';
import { DynamicBackgroundV3Spec } from './DynamicBackgroundV3Spec';
import { PlayerDynamicBackgroundBinding } from './MiniPlayerBinding';
import { PlayerMorphController } from './PlayerMorphController';
import { PlayerLayoutSpec, PlayerMotionSpec } from './PlayerMotion';

@Component
struct PlayerDynamicBackgroundSurface {
  @ObjectLink @Watch('onPlayerStoreChanged') playerStore: PlayerStore;
  @ObjectLink @Watch('onBindingChanged') binding: PlayerDynamicBackgroundBinding;
  private readonly artworkCoordinator: DynamicBackgroundArtworkCoordinator =
    new DynamicBackgroundArtworkCoordinator('FullPlayerDynamicBackground');
  private mounted: boolean = false;
  private artworkSyncScheduled: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.artworkCoordinator.activate(this.playerStore);
    this.artworkCoordinator.setPaused(!this.binding.active);
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.artworkCoordinator.deactivate();
  }

  onDidBuild(): void {
    this.artworkCoordinator.sync();
  }

  private onBindingChanged(): void {
    this.artworkCoordinator.setPaused(!this.binding.active);
  }

  private onPlayerStoreChanged(): void {
    if (this.artworkSyncScheduled) {
      return;
    }
    this.artworkSyncScheduled = true;
    Promise.resolve().then((): void => {
      this.artworkSyncScheduled = false;
      if (this.mounted) {
        this.artworkCoordinator.sync();
      }
    });
  }

  build() {
    XComponent({
      id: 'wplayer_full_player_dynamic_background_v3',
      type: XComponentType.TEXTURE,
      libraryname: 'wplayerbackground'
    })
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onLoad((context: object): void => {
        const density = this.getUIContext().vp2px(1);
        this.artworkCoordinator.attachNativeContext(
          context as DynamicBackgroundV3NativeContext,
          density,
          DynamicBackgroundV3Spec.DEFAULT_SPEED,
          !this.binding.active
        );
      })
      .onDestroy((): void => this.artworkCoordinator.detachNativeContext())
  }
}

@Component
export struct PlayerDynamicBackgroundLayer {
  @ObjectLink controller: PlayerMorphController;
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink binding: PlayerDynamicBackgroundBinding;
  @Prop collapsedSurfaceColor: string = '';
  @Prop playerThemeBackground: string = '';

  private canvasWidth(): number {
    const width = this.controller.fullPlayerFrame().width;
    return width > 0 ? width : this.controller.rootFrame.width;
  }

  private canvasHeight(): number {
    const height = this.controller.fullPlayerFrame().height;
    return height > 0 ? height : this.controller.rootFrame.height;
  }

  private edgeBleed(): number {
    return PlayerMotionSpec.morphBackgroundEdgeBleed(
      this.controller.playerExpandProgress
    );
  }

  private canvasScaleX(): number {
    return this.canvasWidth() > 0 ? 1 + this.edgeBleed() * 2 / this.canvasWidth() : 1;
  }

  private canvasScaleY(): number {
    return this.canvasHeight() > 0 ? 1 + this.edgeBleed() * 2 / this.canvasHeight() : 1;
  }

  build() {
    Stack() {
      Stack()
        .width(this.canvasWidth())
        .height(this.canvasHeight())
        .position({ x: this.edgeBleed(), y: this.edgeBleed() })
        .backgroundColor(DynamicColor.blendOpaque(
          this.collapsedSurfaceColor,
          this.playerThemeBackground,
          this.controller.clamp(this.controller.playerExpandProgress, 0, 1)
        ))
        .opacity(this.controller.playerMorphBackgroundOpacity)
        .scale({
          x: this.canvasScaleX(),
          y: this.canvasScaleY(),
          centerX: '50%',
          centerY: '50%'
        })

      Stack() {
        PlayerDynamicBackgroundSurface({
          playerStore: this.playerStore,
          binding: this.binding
        })
      }
      .width(this.canvasWidth())
      .height(this.canvasHeight())
      .position({ x: this.edgeBleed(), y: this.edgeBleed() })
      .opacity(PlayerMotionSpec.dynamicBackgroundReveal(
        this.controller.playerExpandProgress
      ))
      .scale({
        x: this.canvasScaleX(),
        y: this.canvasScaleY(),
        centerX: '50%',
        centerY: '50%'
      })
    }
    .width(this.controller.morphValue(
      this.controller.frozenMiniPlayerFrame.width,
      this.controller.fullPlayerFrame().width
    ) + this.edgeBleed() * 2)
    .height(this.controller.morphValue(
      this.controller.frozenMiniPlayerFrame.height,
      this.controller.fullPlayerFrame().height
    ) + this.edgeBleed() * 2)
    .position({ x: 0, y: 0 })
    .translate({
      x: this.controller.morphValue(
        this.controller.frozenMiniPlayerFrame.x,
        this.controller.fullPlayerFrame().x
      ) - this.edgeBleed(),
      y: this.controller.morphValue(
        this.controller.frozenMiniPlayerFrame.y,
        this.controller.fullPlayerFrame().y
      ) - this.edgeBleed()
    })
    .borderRadius(PlayerLayoutSpec.MORPH_SURFACE_RADIUS *
      (1 - this.controller.clamp(this.controller.playerExpandProgress, 0, 1)))
    .clip(true)
    .opacity(this.binding.active ? 1 : 0)
    // Keep the persistent native texture on-screen so its composition context
    // stays warm. While idle the whole background plane sits behind the app;
    // during a morph it moves above navigation but below player foreground.
    .zIndex(this.binding.active ? 1 : -1)
    .hitTestBehavior(HitTestMode.None)
  }
}
