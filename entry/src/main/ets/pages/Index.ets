import {
  HdsBarLayoutMode,
  HdsBarStyle,
  HdsTabs,
  HdsTabsController,
  hdsMaterial
} from '@kit.UIDesignKit';
import { curves, SymbolGlyphModifier, window } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  PlayerFrame,
  PlayerGestureAxis,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec,
  PlayerPoint
} from '../components/player/PlayerMotion';

interface NavigationItem {
  label: string;
  icon: SymbolGlyphModifier;
}

@Entry
@Component
struct Index {
  @Env(SystemProperties.WINDOW_AVOID_AREA) avoidAreasVp: window.UIEnvWindowAvoidAreaInfoVP;
  @State isPlaying: boolean = false;
  @State miniBarExpanded: boolean = false;
  @State miniPlayerOffsetX: number = 0;
  @State playerExpandProgress: number = 0;
  @State playerGestureAxis: PlayerGestureAxis = PlayerGestureAxis.UNDECIDED;
  @State swipeHapticTriggered: boolean = false;
  @State playerMorphPhase: PlayerMorphPhase = PlayerMorphPhase.IDLE;
  @State playerMorphBackgroundOpacity: number = 1;
  @State rootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @State measuredMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  @State frozenMiniPlayerFrame: PlayerFrame = {
    x: 0,
    y: 0,
    width: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE,
    height: PlayerLayoutSpec.DEFAULT_MINI_PLAYER_SIZE
  };
  @State frozenRootFrame: PlayerFrame = { x: 0, y: 0, width: 0, height: 0 };
  @State artworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  @State frozenArtworkTarget: PlayerPoint = {
    x: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_X,
    y: PlayerLayoutSpec.DEFAULT_ARTWORK_TARGET_Y
  };
  private returnToExpandedMiniBar: boolean = false;
  private morphTransitionEpoch: number = 0;

  private readonly tabsController: HdsTabsController = new HdsTabsController();
  private readonly floatingBarBottomMargin: number = 18;
  private readonly floatingCircleRightMargin: number = 16;
  private readonly floatingLargeHorizontalMargin: number = 32;
  private readonly largeLayoutBreakpoint: number = 840;
  private readonly navigationItems: NavigationItem[] = [
    { label: '播放列表', icon: new SymbolGlyphModifier($r('sys.symbol.music_note_list_fill')) },
    { label: '音乐', icon: new SymbolGlyphModifier($r('sys.symbol.music_fill')) },
    { label: '专辑', icon: new SymbolGlyphModifier($r('sys.symbol.opticaldisc')) },
    { label: '更多', icon: new SymbolGlyphModifier($r('sys.symbol.square_fill_grid_2x2')) }
  ];

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private lengthToNumber(value: Length | undefined, fallback: number): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsedValue = Number.parseFloat(value);
      return Number.isNaN(parsedValue) ? fallback : parsedValue;
    }
    return fallback;
  }

  private freezeMiniPlayerGeometry(): void {
    this.returnToExpandedMiniBar = this.miniBarExpanded;
    try {
      const uiContext = this.getUIContext();
      const componentUtils = uiContext.getComponentUtils();
      const miniPlayerRectangle = componentUtils.getRectangleById('mini_player_surface');
      const rootRectangle = componentUtils.getRectangleById('player_page_root');
      const floatingBarMargin = uiContext.vp2px(this.floatingBarBottomMargin);
      const usesLargeLayout = uiContext.px2vp(rootRectangle.size.width) >= this.largeLayoutBreakpoint;
      const horizontalMargin = uiContext.vp2px(
        usesLargeLayout ? this.floatingLargeHorizontalMargin : this.floatingCircleRightMargin
      );
      const visibleMiniPlayerX = this.miniBarExpanded ?
        (usesLargeLayout ?
          rootRectangle.windowOffset.x + rootRectangle.size.width - miniPlayerRectangle.size.width - horizontalMargin :
          rootRectangle.windowOffset.x + (rootRectangle.size.width - miniPlayerRectangle.size.width) / 2) :
        rootRectangle.windowOffset.x + rootRectangle.size.width - miniPlayerRectangle.size.width -
          horizontalMargin;
      const visibleMiniPlayerY = miniPlayerRectangle.windowOffset.y - floatingBarMargin;
      this.frozenMiniPlayerFrame = {
        x: uiContext.px2vp(visibleMiniPlayerX - rootRectangle.windowOffset.x),
        y: uiContext.px2vp(visibleMiniPlayerY - rootRectangle.windowOffset.y),
        width: uiContext.px2vp(miniPlayerRectangle.size.width),
        height: uiContext.px2vp(miniPlayerRectangle.size.height)
      };
      this.frozenRootFrame = {
        x: 0,
        y: 0,
        width: uiContext.px2vp(rootRectangle.size.width),
        height: uiContext.px2vp(rootRectangle.size.height)
      };
      this.frozenArtworkTarget = { x: this.artworkTarget.x, y: this.artworkTarget.y };
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to query mini player geometry: ${businessError.code}, ${businessError.message}`);
      this.frozenMiniPlayerFrame = {
        x: this.measuredMiniPlayerFrame.x - this.rootFrame.x,
        y: this.measuredMiniPlayerFrame.y - this.rootFrame.y,
        width: this.measuredMiniPlayerFrame.width,
        height: this.measuredMiniPlayerFrame.height
      };
      this.frozenRootFrame = {
        x: 0,
        y: 0,
        width: this.rootFrame.width,
        height: this.rootFrame.height
      };
      this.frozenArtworkTarget = { x: this.artworkTarget.x, y: this.artworkTarget.y };
    }
  }

  private morphValue(start: number, end: number): number {
    const progress = this.clamp(this.playerExpandProgress, 0, 1);
    return start + (end - start) * progress;
  }

  private morphArtworkShadowColor(): string {
    const progress = this.clamp(this.playerExpandProgress, 0, 1);
    const alpha = Math.round(0x3A * progress).toString(16).padStart(2, '0').toUpperCase();
    return `#${alpha}30319B`;
  }

  private morphArtworkScale(): number {
    return this.morphValue(
      PlayerLayoutSpec.MINI_ARTWORK_SIZE,
      PlayerLayoutSpec.FULL_ARTWORK_SIZE
    ) / PlayerLayoutSpec.FULL_ARTWORK_SIZE;
  }

  private morphArtworkSourceRadius(): number {
    return this.morphValue(
      PlayerLayoutSpec.MINI_ARTWORK_RADIUS,
      PlayerLayoutSpec.FULL_ARTWORK_RADIUS
    ) / this.morphArtworkScale();
  }

  private isMorphActive(): boolean {
    return this.playerMorphPhase !== PlayerMorphPhase.IDLE;
  }

  private beginMorphPhase(phase: PlayerMorphPhase): number {
    this.morphTransitionEpoch += 1;
    this.playerMorphPhase = phase;
    return this.morphTransitionEpoch;
  }

  private isCurrentMorphTransition(epoch: number): boolean {
    return epoch === this.morphTransitionEpoch;
  }

  private beginMorphBackgroundHandoff(epoch: number): void {
    if (!this.isCurrentMorphTransition(epoch)) {
      return;
    }
    this.playerMorphPhase = PlayerMorphPhase.BACKGROUND_HANDOFF;
    this.getUIContext().animateTo({
      duration: PlayerMotionSpec.BACKGROUND_HANDOFF_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        if (!this.isCurrentMorphTransition(epoch)) {
          return;
        }
        this.playerMorphPhase = PlayerMorphPhase.IDLE;
        this.playerMorphBackgroundOpacity = 1;
      }
    }, () => {
      this.playerMorphBackgroundOpacity = 0;
    });
  }

  private triggerSwipeHaptic(): void {
    const effectId: string = 'haptic.effect.soft';
    try {
      if (!vibrator.isSupportEffectSync(effectId)) {
        return;
      }
      vibrator.startVibration({
        type: 'preset',
        effectId: effectId,
        count: 1,
        intensity: 35
      }, {
        id: 0,
        usage: 'touch'
      }).catch((error: BusinessError) => {
        console.warn(`Mini player haptic failed: ${error.code}, ${error.message}`);
      });
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Mini player haptic unavailable: ${businessError.code}, ${businessError.message}`);
    }
  }

  private updateMiniPlayerGesture(event: GestureEvent): void {
    const horizontalDistance = Math.abs(event.offsetX);
    const upwardDistance = Math.max(0, -event.offsetY);
    const verticalDistance = Math.abs(event.offsetY);
    if (this.playerGestureAxis === PlayerGestureAxis.UNDECIDED &&
      Math.max(horizontalDistance, verticalDistance) > PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE) {
      this.playerGestureAxis = horizontalDistance > verticalDistance ?
        PlayerGestureAxis.HORIZONTAL : PlayerGestureAxis.VERTICAL;
    }

    if (this.playerGestureAxis === PlayerGestureAxis.HORIZONTAL) {
      this.miniPlayerOffsetX = event.offsetX /
        (1 + horizontalDistance / PlayerMotionSpec.HORIZONTAL_SWIPE_RESISTANCE);
      const reachedActionPoint = Math.abs(this.miniPlayerOffsetX) >=
        PlayerMotionSpec.HORIZONTAL_HAPTIC_THRESHOLD;
      if (reachedActionPoint && !this.swipeHapticTriggered) {
        this.swipeHapticTriggered = true;
        this.triggerSwipeHaptic();
      }
      return;
    }

    if (this.playerGestureAxis === PlayerGestureAxis.VERTICAL) {
      if (!this.isMorphActive()) {
        this.beginMorphPhase(PlayerMorphPhase.DRAGGING);
        this.playerMorphBackgroundOpacity = 1;
      }
      this.playerExpandProgress = this.clamp(
        upwardDistance / PlayerMotionSpec.DRAG_DISTANCE,
        0,
        1
      );
    }
  }

  private finishMiniPlayerGesture(): void {
    const wasVerticalGesture = this.playerGestureAxis === PlayerGestureAxis.VERTICAL;
    const shouldExpand = wasVerticalGesture &&
      this.playerExpandProgress >= PlayerMotionSpec.EXPAND_THRESHOLD;
    const duration = shouldExpand ? PlayerMotionSpec.OPEN_DURATION : PlayerMotionSpec.CANCEL_DURATION;
    const epoch = wasVerticalGesture ? this.beginMorphPhase(
      shouldExpand ? PlayerMorphPhase.OPENING : PlayerMorphPhase.CLOSING
    ) : this.morphTransitionEpoch;
    this.getUIContext().animateTo({
      duration: duration,
      curve: shouldExpand ? curves.springMotion(0.5, 0.7) : Curve.EaseOut,
      onFinish: () => {
        if (!wasVerticalGesture || !this.isCurrentMorphTransition(epoch)) {
          return;
        }
        if (shouldExpand) {
          this.playerMorphPhase = PlayerMorphPhase.OPEN;
        } else {
          this.beginMorphBackgroundHandoff(epoch);
        }
      }
    }, () => {
      this.miniPlayerOffsetX = 0;
      this.playerExpandProgress = shouldExpand ? 1 : 0;
    });
    this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
    this.swipeHapticTriggered = false;
  }

  private showFullPlayer(): void {
    if (!this.miniBarExpanded) {
      this.tabsController.applyMiniBarStyle(HdsBarStyle.EXPAND);
      return;
    }
    this.freezeMiniPlayerGeometry();
    const epoch = this.beginMorphPhase(PlayerMorphPhase.OPENING);
    this.playerMorphBackgroundOpacity = 1;
    this.getUIContext().animateTo({
      duration: PlayerMotionSpec.OPEN_DURATION,
      curve: curves.springMotion(0.5, 0.7),
      onFinish: () => {
        if (this.isCurrentMorphTransition(epoch)) {
          this.playerMorphPhase = PlayerMorphPhase.OPEN;
        }
      }
    }, () => {
      this.playerExpandProgress = 1;
    });
  }

  private hideFullPlayer(): void {
    if (this.playerMorphPhase === PlayerMorphPhase.IDLE ||
      this.playerMorphPhase === PlayerMorphPhase.CLOSING ||
      this.playerMorphPhase === PlayerMorphPhase.BACKGROUND_HANDOFF) {
      return;
    }
    if (this.miniBarExpanded !== this.returnToExpandedMiniBar) {
      this.tabsController.applyMiniBarStyle(
        this.returnToExpandedMiniBar ? HdsBarStyle.EXPAND : HdsBarStyle.COLLAPSE
      );
    }
    const epoch = this.beginMorphPhase(PlayerMorphPhase.CLOSING);
    this.getUIContext().animateTo({
      duration: PlayerMotionSpec.CLOSE_DURATION,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.beginMorphBackgroundHandoff(epoch);
      }
    }, () => {
      this.playerExpandProgress = 0;
    });
  }

  @Builder
  private BackgroundDecoration() {
    Stack() {
      Column()
        .width(270)
        .height(270)
        .borderRadius(135)
        .backgroundColor('#285B5CE2')
        .blur(52)
        .position({ x: -110, y: 70 })

      Column()
        .width(240)
        .height(240)
        .borderRadius(120)
        .backgroundColor('#22F0A66A')
        .blur(56)
        .position({ x: '60%', y: '56%' })

      Column()
        .width(200)
        .height(200)
        .borderRadius(100)
        .backgroundColor('#204CB6D6')
        .blur(48)
        .position({ x: '58%', y: -60 })
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 145,
      colors: [['#F7F7FC', 0.0], ['#EFF0FA', 0.52], ['#F7F5F3', 1.0]]
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private EmptyPage() {
    Blank()
      .width('100%')
      .height('100%')
  }

  @Builder
  private AlbumCover(size: number, radius: number) {
    Image($r('app.media.default_album_cover'))
      .width(size)
      .height(size)
      .objectFit(ImageFit.Cover)
      .borderRadius(radius)
      .clip(true)
  }

  @Builder
  private PlaybackButton(size: number) {
    Stack() {
      SymbolGlyph(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play_fill'))
        .fontSize(size * 0.42)
        .fontColor(['#FFFFFF'])
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor('#5B5CE2')
    .shadow({ radius: 12, color: '#305B5CE2', offsetY: 5 })
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .accessibilityText(this.isPlaying ? '暂停' : '播放')
    .onClick(() => {
      this.isPlaying = !this.isPlaying;
    })
  }

  @Builder
  private MiniPlayerContent(showArtwork: boolean, followsSwipeOffset: boolean) {
    Row({ space: 10 }) {
      Stack() {
        if (showArtwork) {
          this.AlbumCover(PlayerLayoutSpec.MINI_ARTWORK_SIZE, PlayerLayoutSpec.MINI_ARTWORK_RADIUS)
        }
      }
      .width(48)
      .height(48)
      .zIndex(2)
      .onClick(() => {
        this.showFullPlayer();
      })

      if (this.miniBarExpanded) {
        Column({ space: 2 }) {
          Text('尚未播放')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor('#252934')
            .maxLines(1)

          Text('选择一首音乐')
            .fontSize(11)
            .fontColor('#737987')
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .translate({ x: followsSwipeOffset ? this.miniPlayerOffsetX : 0 })
        .onClick(() => {
          this.showFullPlayer();
        })

        this.PlaybackButton(40)
      }
    }
    .height(56)
    .width('100%')
    .padding({ left: 4, right: this.miniBarExpanded ? 8 : 4 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(28)
    .clip(true)
  }

  @Builder
  private MiniPlayer() {
    Stack() {
      this.MiniPlayerContent(true, true)
    }
    .height(56)
    .width('100%')
    .id('mini_player_surface')
    .borderRadius(28)
    .clip(true)
    .opacity(this.isMorphActive() ? 0 : 1)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.measuredMiniPlayerFrame = {
        x: this.lengthToNumber(newValue.globalPosition.x, this.measuredMiniPlayerFrame.x),
        y: this.lengthToNumber(newValue.globalPosition.y, this.measuredMiniPlayerFrame.y),
        width: this.lengthToNumber(newValue.width, this.measuredMiniPlayerFrame.width),
        height: this.lengthToNumber(newValue.height, this.measuredMiniPlayerFrame.height)
      };
    })
    .parallelGesture(
      PanGesture({ direction: PanDirection.All, distance: 3 })
        .onActionStart(() => {
          this.playerGestureAxis = PlayerGestureAxis.UNDECIDED;
          this.freezeMiniPlayerGeometry();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateMiniPlayerGesture(event);
        })
        .onActionEnd(() => {
          this.finishMiniPlayerGesture();
        })
        .onActionCancel(() => {
          this.finishMiniPlayerGesture();
        })
    )
  }

  @Builder
  private PlayerTabs() {
    HdsTabs({ controller: this.tabsController }) {
      ForEach(this.navigationItems, (item: NavigationItem) => {
        TabContent() {
          this.EmptyPage()
        }
        .tabBar(new BottomTabBarStyle({ normal: item.icon }, item.label))
      }, (item: NavigationItem) => item.label)
    }
    .width('100%')
    .height('100%')
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .scrollable(true)
    .barFloatingStyle({
      barWidth: { smallWidth: 300, mediumWidth: 320, largeWidth: 328 },
      barBottomMargin: this.floatingBarBottomMargin,
      gradientMask: { maskColor: $r('app.color.float_bar_gradient_mask'), maskHeight: 84 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      miniBar: {
        miniBarBuilder: () => this.MiniPlayer(),
        miniBarWidth: { smallWidth: 270, mediumWidth: 300, largeWidth: 328 },
        miniBarStyle: HdsBarStyle.COLLAPSE,
        barLayoutMode: HdsBarLayoutMode.HORIZONTAL,
        onBarStyleChange: (miniBarStyle: HdsBarStyle) => {
          this.miniBarExpanded = miniBarStyle === HdsBarStyle.EXPAND;
        },
        enableMiniBarBackground: true,
        enableMiniBarClip: true
      }
    })
  }

  @Builder
  private FullPlayerControl(icon: Resource, accessibilityText: string, size: number) {
    Stack() {
      Image(icon)
        .width(size * 0.45)
        .height(size * 0.45)
        .fillColor('#2D303B')
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor('#38FFFFFF')
    .clickEffect({ level: ClickEffectLevel.MIDDLE })
    .accessibilityText(accessibilityText)
  }

  @Builder
  private FullPlayerContent(showArtwork: boolean, measuresArtworkTarget: boolean = false) {
    Column() {
      Row() {
        Stack() {
          Image($r('app.media.control_chevron_down'))
            .width(22)
            .height(22)
            .fillColor('#252934')
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor('#52FFFFFF')
        .backgroundBlurStyle(BlurStyle.Thin)
        .clickEffect({ level: ClickEffectLevel.MIDDLE })
        .accessibilityText('收起播放器')
        .onClick(() => {
          this.hideFullPlayer();
        })

        Text('正在播放')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#252934')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank().width(44)
      }
      .width('100%')

      Blank().layoutWeight(1)

      Stack() {
        if (showArtwork) {
          this.AlbumCover(PlayerLayoutSpec.FULL_ARTWORK_SIZE, PlayerLayoutSpec.FULL_ARTWORK_RADIUS)
        }
      }
      .width(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
      .height(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
      .borderRadius(PlayerLayoutSpec.FULL_ARTWORK_SIZE / 2)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        if (!measuresArtworkTarget) {
          return;
        }
        this.artworkTarget = {
          x: this.lengthToNumber(
            newValue.globalPosition.x,
            this.artworkTarget.x + this.rootFrame.x
          ) - this.rootFrame.x,
          y: this.lengthToNumber(
            newValue.globalPosition.y,
            this.artworkTarget.y + this.rootFrame.y
          ) - this.rootFrame.y
        };
      })

      Blank().layoutWeight(1)

      Column({ space: 7 }) {
        Text('尚未播放')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#20232C')
        Text('选择一首音乐开始播放')
          .fontSize(15)
          .fontColor('#747987')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')

      Row() {
        this.FullPlayerControl($r('app.media.control_previous'), '上一首', 54)
        this.PlaybackButton(74)
        this.FullPlayerControl($r('app.media.control_next'), '下一首', 54)
      }
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .margin({ top: 30, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 28,
      right: 28,
      top: this.avoidAreasVp.statusBar.topRect.height + 18,
      bottom: this.avoidAreasVp.navigationIndicator.bottomRect.height + 10
    })
  }

  @Builder
  private MorphPlayer() {
    Stack() {
      Stack() {
      }
      .width('100%')
      .height('100%')
      .linearGradient({
        angle: 180,
        colors: [['#EDEEFF', 0.0], ['#F8F8FC', 0.55], ['#F2F1F5', 1.0]]
      })
      .opacity(this.playerMorphBackgroundOpacity)

      Stack() {
        Stack() {
          this.FullPlayerContent(false, false)
        }
        .width(this.frozenRootFrame.width)
        .height(this.frozenRootFrame.height)
        .position({ x: 0, y: 0 })
        .opacity(this.clamp(
          (this.playerExpandProgress - PlayerMotionSpec.FULL_CONTENT_FADE_START) *
            PlayerMotionSpec.FULL_CONTENT_FADE_RATE,
          0,
          1
        ))

        if (this.playerExpandProgress < PlayerMotionSpec.MINI_CONTENT_VISIBLE_LIMIT) {
          Stack() {
            this.MiniPlayerContent(false, false)
          }
          .width('100%')
          .height('100%')
          .opacity(1 - this.clamp(
            (this.playerExpandProgress - PlayerMotionSpec.MINI_CONTENT_FADE_START) *
              PlayerMotionSpec.MINI_CONTENT_FADE_RATE,
            0,
            1
          ))
        }
      }
      .width('100%')
      .height('100%')
    }
    .width(this.morphValue(this.frozenMiniPlayerFrame.width, this.frozenRootFrame.width))
    .height(this.morphValue(this.frozenMiniPlayerFrame.height, this.frozenRootFrame.height))
    .position({ x: 0, y: 0 })
    .translate({
      x: this.morphValue(this.frozenMiniPlayerFrame.x, this.frozenRootFrame.x),
      y: this.morphValue(this.frozenMiniPlayerFrame.y, this.frozenRootFrame.y)
    })
    .borderRadius(28 * (1 - this.clamp(this.playerExpandProgress, 0, 1)))
    .clip(true)
  }

  @Builder
  private MorphArtwork() {
    Stack() {
      Image($r('app.media.default_album_cover'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(this.morphArtworkSourceRadius())
        .clip(true)
    }
    .width(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
    .height(PlayerLayoutSpec.FULL_ARTWORK_SIZE)
    .borderRadius(this.morphArtworkSourceRadius())
    .position({ x: 0, y: 0 })
    .translate({
      x: this.morphValue(
        this.frozenMiniPlayerFrame.x + PlayerLayoutSpec.MINI_ARTWORK_INSET,
        this.frozenArtworkTarget.x
      ),
      y: this.morphValue(
        this.frozenMiniPlayerFrame.y + PlayerLayoutSpec.MINI_ARTWORK_INSET,
        this.frozenArtworkTarget.y
      )
    })
    .scale({
      x: this.morphArtworkScale(),
      y: this.morphArtworkScale(),
      centerX: 0,
      centerY: 0
    })
    .shadow({
      radius: 38,
      color: this.morphArtworkShadowColor(),
      offsetY: 20
    })
  }

  @Builder
  private FullPlayerGeometryProbe() {
    Stack() {
      this.FullPlayerContent(false, true)
    }
    .width('100%')
    .height('100%')
    .opacity(0)
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack() {
      this.FullPlayerGeometryProbe()

      this.BackgroundDecoration()
      this.PlayerTabs()

      if (this.isMorphActive()) {
        this.MorphPlayer()
        this.MorphArtwork()
      }
    }
    .width('100%')
    .height('100%')
    .id('player_page_root')
    .backgroundColor('#F4F4FA')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.rootFrame = {
        x: this.lengthToNumber(newValue.globalPosition.x, this.rootFrame.x),
        y: this.lengthToNumber(newValue.globalPosition.y, this.rootFrame.y),
        width: this.lengthToNumber(newValue.width, this.rootFrame.width),
        height: this.lengthToNumber(newValue.height, this.rootFrame.height)
      };
    })
  }
}
