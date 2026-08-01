import { image } from '@kit.ImageKit';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import { PlayerStore, QueueTrack } from '../../playback/model/PlaybackModels';
import { FullPlayerContent } from './FullPlayerContent';
import { MiniPlayerContent } from './MiniPlayerSurface';
import { PlayerPlaybackButton } from './PlayerControls';
import { PlayerMorphArtwork } from './PlayerMorphArtwork';
import { PlayerMorphController } from './PlayerMorphController';
import { AppSettingsStore } from '../../settings/AppSettingsStore';
import { LibraryStore } from '../../library/store/LibraryStore';
import {
  AvailabilityState,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
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
  @ObjectLink libraryStore: LibraryStore;
  @ObjectLink settingsStore: AppSettingsStore;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop primaryContentColor: string = '';
  onRequestAddToPlaylist: (trackIds: Array<number>) => void =
    (_trackIds: Array<number>): void => {};
  onOpenTrackActions: (trackId: number, anchorId: string) => void =
    (_trackId: number, _anchorId: string): void => {};
  onOpenTrackDetails: (track: TrackListItem) => void =
    (_track: TrackListItem): void => {};
  onNavigateLibrary: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onShareTrackFile: (trackId: number) => void = (_trackId: number): void => {};
  onOpenPlayerPageSettings: () => void = (): void => {};

  private currentTrackItem(track: QueueTrack): TrackListItem {
    return {
      id: track.id,
      title: track.title,
      artistDisplay: track.artistDisplay,
      albumDisplay: track.albumDisplay,
      durationMs: track.durationMs,
      trackNumber: 0,
      discNumber: 0,
      smallArtworkHash: track.smallArtworkHash,
      smallArtworkPath: track.smallArtworkPath,
      artworkHash: track.largeArtworkHash,
      artworkPath: track.largeArtworkPath,
      artworkWidth: track.artworkWidth,
      artworkHeight: track.artworkHeight,
      palettePrimary: track.palettePrimary,
      paletteSecondary: track.paletteSecondary,
      paletteAccent: track.paletteAccent,
      sectionKey: '',
      availability: AvailabilityState.AVAILABLE
    };
  }

  private addCurrentTrackToPlaylist(): void {
    if (this.playerStore.currentTrack !== undefined) {
      this.onRequestAddToPlaylist([this.playerStore.currentTrack.id]);
    }
  }

  private openCurrentTrackDetails(): void {
    if (this.playerStore.currentTrack !== undefined) {
      this.onOpenTrackDetails(this.currentTrackItem(this.playerStore.currentTrack));
    }
  }

  @Builder
  private MorphPlayer() {
    Stack() {
      Stack() {
        Stack() {
          FullPlayerContent({
            playerStore: this.playerStore,
            libraryStore: this.libraryStore,
            marqueeActive: this.controller.playerMorphPhase === PlayerMorphPhase.OPEN,
            topInset: this.topInset,
            bottomInset: this.bottomInset,
            showArtwork: false,
            showPlaybackButton: this.controller.shouldShowFullPlaybackButton(),
            rootFrame: this.controller.fullPlayerFrame(),
            pagePosition: this.controller.fullPlayerPagePosition,
            paneCount: this.controller.renderedFullPlayerPaneCount(),
            activePage: this.controller.fullPlayerPage,
            sideContentReady: this.controller.shouldRenderFullPlayerSideContent(),
            pageScrollingEnabled: this.controller.playerMorphPhase === PlayerMorphPhase.OPEN,
            primaryContentColor: this.primaryContentColor,
            showFloatingWindowButton: this.settingsStore.playerPageShowFloatingWindowButton,
            lyricBlurEffectEnabled: this.settingsStore.playerPageLyricBlurEffect,
            previousArtworkFrame: this.controller.artworkTarget,
            previousCenteredArtworkFrame: this.controller.centeredArtworkTarget,
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
              this.onOpenTrackActions(trackId, anchorId),
            onOpenTrackDetails: (track: TrackListItem): void =>
              this.onOpenTrackDetails(track),
            onShareTrackFile: this.onShareTrackFile,
            onNavigateLibrary: this.onNavigateLibrary,
            onOpenPlayerPageSettings: this.onOpenPlayerPageSettings
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
              showPlaybackButton: false,
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
      geometryProgress: this.controller.morphGeometryProgress(),
      positionProgress: this.controller.morphPositionProgress(),
      elementOpacity: this.controller.morphElementOpacity(),
      morphPhase: this.controller.playerMorphPhase,
      topInset: this.topInset,
      bottomInset: this.bottomInset,
      frozenMiniPlayerFrame: this.controller.frozenMiniPlayerFrame,
      fullPlayerFrame: this.controller.fullPlayerFrame(),
      fullPlayerArtworkTarget: this.controller.fullPlayerArtworkTarget(),
      sourceWidth: this.controller.morphArtworkSourceWidth(),
      sourceHeight: this.controller.morphArtworkSourceHeight(),
      sourceProvider: (): image.PixelMap | ResourceStr => this.controller.morphArtworkSource(),
      onInsertNext: (): void => playbackRuntime.insertCurrentNext(),
      onAppendToQueue: (): void => playbackRuntime.appendCurrentToQueue(),
      onAddToPlaylist: (): void => this.addCurrentTrackToPlaylist(),
      onOpenDetails: (): void => this.openCurrentTrackDetails(),
      onShareTrackFile: (): void => {
        if (this.playerStore.currentTrack !== undefined) {
          this.onShareTrackFile(this.playerStore.currentTrack.id);
        }
      },
      onCompletedCollectionChange: (enabled: boolean): void =>
        playbackRuntime.setCompletedCollectionEnabled(enabled)
    })
  }

  @Builder
  private MorphPlaybackButton() {
    if (this.controller.shouldRenderPlaybackButtonProxy()) {
      PlayerPlaybackButton({
        playerStore: this.playerStore,
        buttonSize: this.controller.morphPlaybackButtonFrame().width,
        iconSize: this.controller.morphPlaybackButtonIconSize(),
        iconAnimationEnabled: false,
        contentColor: this.controller.morphPlaybackButtonColor()
      })
        .opacity(this.controller.morphPlaybackButtonOpacity())
        .position({ x: 0, y: 0 })
        .translate({
          x: this.controller.morphPlaybackButtonFrame().x,
          y: this.controller.morphPlaybackButtonFrame().y
        })
    }
  }

  build() {
    Stack() {
      Stack() {
        this.MorphPlayer()

        Stack() {
          this.MorphArtwork()
          this.MorphPlaybackButton()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
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
    .zIndex(2)
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
