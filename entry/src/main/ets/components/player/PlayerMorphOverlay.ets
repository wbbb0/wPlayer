import { DynamicColor } from '../../appearance/DynamicColor';
import { image } from '@kit.ImageKit';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore } from '../../playback/model/PlaybackModels';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { FullPlayerContent } from './FullPlayerContent';
import { MiniPlayerContent } from './MiniPlayerSurface';
import { PlayerMorphArtwork } from './PlayerMorphArtwork';
import { PlayerMorphController } from './PlayerMorphController';
import {
  FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID,
  FULL_PLAYER_VERTICAL_GESTURE_HOST_ID,
  FullPlayerPage,
  PlayerLayoutSpec,
  PlayerMorphPhase,
  PlayerMotionSpec
} from './PlayerMotion';

@Component
export struct PlayerMorphOverlay {
  @ObjectLink controller: PlayerMorphController;
  @ObjectLink playerStore: PlayerStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop collapsedSurfaceColor: string = '';
  @Prop playerThemeBackground: string = '';
  @Prop primaryContentColor: string = '';
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};
  onOpenTrackActions: (trackId: number, anchorId: string) => void =
    (_trackId: number, _anchorId: string): void => {};

  @Builder
  private MorphPlayer() {
    Stack() {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor(DynamicColor.blendOpaque(
          this.collapsedSurfaceColor,
          this.playerThemeBackground,
          this.controller.clamp(this.controller.playerExpandProgress, 0, 1)
        ))
        .opacity(this.controller.playerMorphBackgroundOpacity)

      Stack() {
        Stack() {
          FullPlayerContent({
            playerStore: this.playerStore,
            marqueeActive: this.controller.playerMorphPhase === PlayerMorphPhase.OPEN,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            showArtwork: false,
            heroArtworkInterpolation: this.settingsStore.highQualityHeroArtwork ?
              ImageInterpolation.High : ImageInterpolation.Medium,
            rootFrame: this.controller.fullPlayerFrame(),
            pagePosition: this.controller.fullPlayerPagePosition,
            paneCount: this.controller.renderedFullPlayerPaneCount(),
            primaryContentColor: this.primaryContentColor,
            previousArtworkTarget: this.controller.artworkTarget,
            previousCenteredArtworkTarget: this.controller.centeredArtworkTarget,
            onClose: (): void => this.controller.hideFullPlayer(),
            onNavigatePage: (page: FullPlayerPage): void =>
              this.controller.navigateFullPlayerPage(page),
            onPlayQueueTrack: (trackId: number): void => playbackRuntime.playQueueTrack(trackId),
            onSeek: (positionMs: number): void => playbackRuntime.seek(positionMs),
            onCompletedCollectionChange: (enabled: boolean): void =>
              playbackRuntime.setCompletedCollectionEnabled(enabled),
            onRequestAddToPlaylist: (trackIds: Array<number>): void =>
              this.onRequestAddToPlaylist(trackIds),
            onResolveQueueArtwork: (relativePath: string): string =>
              playbackRuntime.queueArtworkUri(relativePath),
            onOpenTrackActions: (trackId: number, anchorId: string): void =>
              this.onOpenTrackActions(trackId, anchorId)
          })
        }
        .width(this.controller.fullPlayerFrame().width)
        .height(this.controller.fullPlayerFrame().height)
        .position({ x: 0, y: 0 })
        .opacity(PlayerMotionSpec.fullContentOpacity(this.controller.playerExpandProgress))

        if (this.controller.playerExpandProgress < PlayerMotionSpec.MINI_CONTENT_VISIBLE_LIMIT) {
          Stack() {
            MiniPlayerContent({
              playerStore: this.playerStore,
              binding: this.controller.miniPlayerBinding,
              showArtwork: false,
              followsSwipeOffset: false,
              marqueeActive: false,
              onShowFullPlayer: (): void => this.controller.showFullPlayer()
            })
          }
          .width('100%')
          .height('100%')
          .opacity(1 - this.controller.clamp(
            (this.controller.playerExpandProgress - PlayerMotionSpec.MINI_CONTENT_FADE_START) *
              PlayerMotionSpec.MINI_CONTENT_FADE_RATE,
            0,
            1
          ))
        }
      }
      .width('100%')
      .height('100%')
    }
    .width(this.controller.morphValue(
      this.controller.frozenMiniPlayerFrame.width,
      this.controller.fullPlayerFrame().width
    ))
    .height(this.controller.morphValue(
      this.controller.frozenMiniPlayerFrame.height,
      this.controller.fullPlayerFrame().height
    ))
    .position({ x: 0, y: 0 })
    .translate({
      x: this.controller.morphValue(
        this.controller.frozenMiniPlayerFrame.x,
        this.controller.fullPlayerFrame().x
      ),
      y: this.controller.morphValue(
        this.controller.frozenMiniPlayerFrame.y,
        this.controller.fullPlayerFrame().y
      )
    })
    .borderRadius(PlayerLayoutSpec.MORPH_SURFACE_RADIUS *
      (1 - this.controller.clamp(this.controller.playerExpandProgress, 0, 1)))
    .clip(true)
  }

  @Builder
  private MorphArtwork() {
    PlayerMorphArtwork({
      playerStore: this.playerStore,
      settingsStore: this.settingsStore,
      expandProgress: this.controller.playerExpandProgress,
      morphPhase: this.controller.playerMorphPhase,
      fullPlayerPage: this.controller.fullPlayerPage,
      fullPlayerPagePosition: this.controller.fullPlayerPagePosition,
      renderedPaneCount: this.controller.renderedFullPlayerPaneCount(),
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      frozenMiniPlayerFrame: this.controller.frozenMiniPlayerFrame,
      fullPlayerFrame: this.controller.fullPlayerFrame(),
      fullPlayerArtworkTarget: this.controller.fullPlayerArtworkTarget(),
      sourceWidth: this.controller.morphArtworkSourceWidth(),
      sourceHeight: this.controller.morphArtworkSourceHeight(),
      sourceProvider: (): image.PixelMap | ResourceStr => this.controller.morphArtworkSource()
    })
  }

  build() {
    Stack() {
      Stack() {
        this.MorphPlayer()

        Stack() {
          this.MorphArtwork()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .id(FULL_PLAYER_HORIZONTAL_GESTURE_HOST_ID)
      .parallelGesture(
        PanGesture({
          direction: PanDirection.Horizontal,
          distance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE
        })
          .onActionStart(() => {
            this.controller.beginFullPlayerHorizontalGesture();
          })
          .onActionUpdate((event: GestureEvent) => {
            this.controller.updateFullPlayerHorizontalGesture(event);
          })
          .onActionEnd(() => {
            this.controller.finishFullPlayerHorizontalGesture();
          })
          .onActionCancel(() => {
            this.controller.finishFullPlayerHorizontalGesture();
          })
      )
    }
    .width('100%')
    .height('100%')
    .id(FULL_PLAYER_VERTICAL_GESTURE_HOST_ID)
    .parallelGesture(
      PanGesture({
        direction: PanDirection.Vertical,
        distance: PlayerMotionSpec.GESTURE_AXIS_LOCK_DISTANCE
      })
        .onActionStart(() => {
          this.controller.beginFullPlayerVerticalGesture();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.controller.updateFullPlayerVerticalGesture(event);
        })
        .onActionEnd(() => {
          this.controller.finishFullPlayerVerticalGesture();
        })
        .onActionCancel(() => {
          this.controller.finishFullPlayerVerticalGesture();
        })
    )
  }
}
