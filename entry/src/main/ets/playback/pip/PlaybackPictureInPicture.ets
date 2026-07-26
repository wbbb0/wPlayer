import {
  BuilderNode,
  FrameNode,
  NodeController,
  PiPWindow,
  typeNode,
  UIContext,
  window
} from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BundledArtworkCatalog } from '../../library/artwork/BundledArtworkCatalog';
import {
  PlaybackPictureInPicturePolicy,
  PlaybackPictureInPictureSize
} from './PlaybackPictureInPicturePolicy';

export interface PlaybackPictureInPictureCommands {
  play(): void;
  pause(): void;
  previous(): void;
  next(): void;
}

export class PlaybackPictureInPictureSnapshot {
  readonly trackId: number;
  readonly artworkUri: string;
  readonly artworkWidth: number;
  readonly artworkHeight: number;
  readonly hasCurrentTrack: boolean;
  readonly playing: boolean;
  readonly transportControlsEnabled: boolean;

  constructor(trackId: number, artworkUri: string, artworkWidth: number, artworkHeight: number,
    hasCurrentTrack: boolean, playing: boolean, transportControlsEnabled: boolean) {
    this.trackId = trackId;
    this.artworkUri = artworkUri;
    this.artworkWidth = artworkWidth;
    this.artworkHeight = artworkHeight;
    this.hasCurrentTrack = hasCurrentTrack;
    this.playing = playing;
    this.transportControlsEnabled = transportControlsEnabled;
  }
}

enum PlaybackPictureInPicturePhase {
  IDLE,
  CREATING,
  READY,
  STARTING,
  STARTED,
  STOPPING
}

class PlaybackPictureInPictureArtworkParams {
  readonly artworkUri: string;

  constructor(artworkUri: string) {
    this.artworkUri = artworkUri;
  }
}

@Builder
function PlaybackPictureInPictureArtwork(params: PlaybackPictureInPictureArtworkParams) {
  Stack({ alignContent: Alignment.Center }) {
    if (params.artworkUri.length > 0) {
      Image(BundledArtworkCatalog.resolve(params.artworkUri))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
    } else {
      Image(BundledArtworkCatalog.resolve(BundledArtworkCatalog.DEFAULT_FULL))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
    }
  }
  .width('100%')
  .height('100%')
  .backgroundColor('#FF000000')
  .hitTestBehavior(HitTestMode.None)
}

class PlaybackPictureInPictureArtworkController extends NodeController {
  private artworkNode: BuilderNode<[PlaybackPictureInPictureArtworkParams]> | null = null;
  private params: PlaybackPictureInPictureArtworkParams =
    new PlaybackPictureInPictureArtworkParams('');

  makeNode(context: UIContext): FrameNode | null {
    if (this.artworkNode === null) {
      this.artworkNode = new BuilderNode(context);
      this.artworkNode.build(
        wrapBuilder<[PlaybackPictureInPictureArtworkParams]>(PlaybackPictureInPictureArtwork),
        this.params
      );
    }
    return this.artworkNode.getFrameNode();
  }

  update(artworkUri: string): void {
    this.params = new PlaybackPictureInPictureArtworkParams(artworkUri);
    this.artworkNode?.update(this.params);
  }

  dispose(): void {
    this.artworkNode?.dispose();
    this.artworkNode = null;
  }
}

export class PlaybackPictureInPicture {
  private readonly commands: PlaybackPictureInPictureCommands;
  private readonly artworkController: PlaybackPictureInPictureArtworkController =
    new PlaybackPictureInPictureArtworkController();
  private readonly xComponentController: XComponentController = new XComponentController();
  private controller?: PiPWindow.PiPController;
  private contentNode: typeNode.XComponent | null = null;
  private phase: PlaybackPictureInPicturePhase = PlaybackPictureInPicturePhase.IDLE;
  private snapshot: PlaybackPictureInPictureSnapshot =
    new PlaybackPictureInPictureSnapshot(-1, '', 0, 0, false, false, false);
  private contentSize: PlaybackPictureInPictureSize =
    PlaybackPictureInPicturePolicy.contentSize(0, 0);
  private enterPromise?: Promise<void>;
  private creationPromise?: Promise<void>;
  private stopPromise?: Promise<void>;
  private stopWhenStarted: boolean = false;
  private autoStartEnabled: boolean = false;

  private readonly stateChangeCallback =
    (state: PiPWindow.PiPState, _reason: string): void => {
      switch (state) {
        case PiPWindow.PiPState.ABOUT_TO_START:
          this.phase = PlaybackPictureInPicturePhase.STARTING;
          break;
        case PiPWindow.PiPState.STARTED:
          this.phase = PlaybackPictureInPicturePhase.STARTED;
          this.syncControls();
          if (this.stopWhenStarted) {
            this.stopWhenStarted = false;
            this.stop().catch((error: Object): void => {
              console.warn(`Unable to stop PiP after startup: ${
                PlaybackPictureInPicture.messageOf(error)
              }`);
            });
          }
          break;
        case PiPWindow.PiPState.ABOUT_TO_STOP:
        case PiPWindow.PiPState.ABOUT_TO_RESTORE:
          this.phase = PlaybackPictureInPicturePhase.STOPPING;
          break;
        case PiPWindow.PiPState.STOPPED:
        case PiPWindow.PiPState.ERROR:
          this.phase = PlaybackPictureInPicturePhase.READY;
          this.stopWhenStarted = false;
          this.artworkController.dispose();
          break;
        default:
          break;
      }
    };

  private readonly controlEventCallback =
    (event: PiPWindow.ControlEventParam): void => {
      switch (event.controlType) {
        case PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE:
          if (event.status === PiPWindow.PiPControlStatus.PLAY) {
            this.commands.play();
          } else if (event.status === PiPWindow.PiPControlStatus.PAUSE) {
            this.commands.pause();
          }
          break;
        case PiPWindow.PiPControlType.VIDEO_PREVIOUS:
          this.commands.previous();
          break;
        case PiPWindow.PiPControlType.VIDEO_NEXT:
          this.commands.next();
          break;
        default:
          break;
      }
    };

  constructor(commands: PlaybackPictureInPictureCommands) {
    this.commands = commands;
  }

  enter(uiContext: UIContext, snapshot: PlaybackPictureInPictureSnapshot,
    autoMinimizeApp: boolean): Promise<void> {
    this.sync(snapshot);
    if (!snapshot.hasCurrentTrack) {
      return Promise.reject(new Error('请先选择一首音乐'));
    }
    if (!PiPWindow.isPiPEnabled()) {
      return Promise.reject(new Error('当前设备未开启画中画功能'));
    }
    if (this.phase === PlaybackPictureInPicturePhase.STARTED ||
      this.phase === PlaybackPictureInPicturePhase.STARTING) {
      return autoMinimizeApp ? this.minimizeHostApplication(uiContext) : Promise.resolve();
    }
    if (this.enterPromise !== undefined) {
      return this.enterPromise;
    }
    this.enterPromise = this.enterInternal(uiContext, autoMinimizeApp).finally((): void => {
      this.enterPromise = undefined;
    });
    return this.enterPromise;
  }

  async configureAutoStart(uiContext: UIContext | undefined, enabled: boolean): Promise<void> {
    const changed = enabled !== this.autoStartEnabled;
    this.autoStartEnabled = enabled;
    if (this.controller !== undefined) {
      if (changed) {
        this.controller.setAutoStartEnabled(enabled);
      }
      return;
    }
    if (!enabled || uiContext === undefined) {
      return;
    }
    await this.ensureController(uiContext);
  }

  sync(snapshot: PlaybackPictureInPictureSnapshot): void {
    const nextSize = PlaybackPictureInPicturePolicy.contentSize(
      snapshot.artworkWidth,
      snapshot.artworkHeight
    );
    const contentChanged = snapshot.trackId !== this.snapshot.trackId ||
      snapshot.artworkUri !== this.snapshot.artworkUri;
    const sizeChanged = nextSize.width !== this.contentSize.width ||
      nextSize.height !== this.contentSize.height;
    this.snapshot = snapshot;
    this.contentSize = nextSize;
    if (contentChanged) {
      this.artworkController.update(snapshot.artworkUri);
    }
    if (sizeChanged && this.controller !== undefined) {
      try {
        this.controller.updateContentSize(nextSize.width, nextSize.height);
      } catch (error) {
        console.warn(`Unable to update PiP content size: ${PlaybackPictureInPicture.messageOf(error)}`);
      }
    }
    if (this.phase === PlaybackPictureInPicturePhase.STARTED) {
      this.syncControls();
    }
  }

  stop(): Promise<void> {
    if (this.phase === PlaybackPictureInPicturePhase.STARTING) {
      this.stopWhenStarted = true;
      return Promise.resolve();
    }
    if (this.phase !== PlaybackPictureInPicturePhase.STARTED ||
      this.controller === undefined) {
      return this.stopPromise ?? Promise.resolve();
    }
    if (this.stopPromise !== undefined) {
      return this.stopPromise;
    }
    try {
      this.stopPromise = this.controller.stopPiP().finally((): void => {
        this.stopPromise = undefined;
      });
    } catch (error) {
      return Promise.reject(error);
    }
    return this.stopPromise;
  }

  async dispose(): Promise<void> {
    this.enterPromise = undefined;
    try {
      await this.creationPromise;
    } catch (_error) {
      // Creation failures are already surfaced to the caller that requested the controller.
    }
    try {
      await this.stopPromise;
    } catch (_error) {
      // Stop failures are handled by the caller that requested the stop.
    }
    const controller = this.controller;
    this.creationPromise = undefined;
    this.stopPromise = undefined;
    this.stopWhenStarted = false;
    if (controller !== undefined) {
      try {
        controller.off('stateChange');
        controller.off('controlEvent', this.controlEventCallback);
        if (this.phase === PlaybackPictureInPicturePhase.STARTED ||
          this.phase === PlaybackPictureInPicturePhase.STARTING) {
          await controller.stopPiP();
        }
      } catch (error) {
        console.warn(`Unable to stop PiP: ${PlaybackPictureInPicture.messageOf(error)}`);
      }
    }
    this.artworkController.dispose();
    this.controller = undefined;
    this.contentNode = null;
    this.phase = PlaybackPictureInPicturePhase.IDLE;
  }

  private async enterInternal(uiContext: UIContext, autoMinimizeApp: boolean): Promise<void> {
    try {
      await this.ensureController(uiContext);
      this.phase = PlaybackPictureInPicturePhase.STARTING;
      await this.controller?.startPiP();
    } catch (error) {
      if (this.phase !== PlaybackPictureInPicturePhase.STARTED) {
        this.phase = this.controller === undefined ?
          PlaybackPictureInPicturePhase.IDLE : PlaybackPictureInPicturePhase.READY;
      }
      const businessError = error as BusinessError;
      const code = businessError.code === undefined ? '' : `（${businessError.code}）`;
      throw new Error(`无法启动画中画${code}`);
    }
    if (autoMinimizeApp) {
      await this.minimizeHostApplication(uiContext);
    }
  }

  private async minimizeHostApplication(uiContext: UIContext): Promise<void> {
    const context = uiContext.getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      throw new Error('画中画已启动，但无法获取主窗口上下文');
    }
    try {
      const mainWindow = await window.getLastWindow(context);
      await mainWindow.minimize();
      return;
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code !== 801) {
        const code = businessError.code === undefined ? '' : `（${businessError.code}）`;
        throw new Error(`画中画已启动，但主窗口无法最小化${code}`);
      }
    }
    try {
      await context.moveAbilityToBackground();
    } catch (error) {
      const businessError = error as BusinessError;
      const code = businessError.code === undefined ? '' : `（${businessError.code}）`;
      throw new Error(`画中画已启动，但主窗口无法退至后台${code}`);
    }
  }

  private ensureController(uiContext: UIContext): Promise<void> {
    if (this.controller !== undefined) {
      return Promise.resolve();
    }
    if (this.creationPromise !== undefined) {
      return this.creationPromise;
    }
    this.creationPromise = this.createController(uiContext).finally((): void => {
      this.creationPromise = undefined;
    });
    return this.creationPromise;
  }

  private async createController(uiContext: UIContext): Promise<void> {
    const context = uiContext.getHostContext();
    if (context === undefined) {
      throw new Error('无法获取主窗口上下文');
    }
    this.phase = PlaybackPictureInPicturePhase.CREATING;
    this.artworkController.update(this.snapshot.artworkUri);
    this.contentNode = typeNode.createNode(uiContext, 'XComponent', {
      type: XComponentType.SURFACE,
      controller: this.xComponentController
    });
    const config: PiPWindow.PiPConfiguration = {
      context: context,
      componentController: this.xComponentController,
      templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
      contentWidth: this.contentSize.width,
      contentHeight: this.contentSize.height,
      controlGroups: [PiPWindow.VideoPlayControlGroup.VIDEO_PREVIOUS_NEXT],
      customUIController: this.artworkController,
      defaultWindowSizeType: 1,
      cornerAdsorptionEnabled: true
    };
    try {
      this.controller = await PiPWindow.create(config, this.contentNode);
    } catch (error) {
      this.phase = PlaybackPictureInPicturePhase.IDLE;
      this.contentNode = null;
      throw new Error(PlaybackPictureInPicture.messageOf(error));
    }
    this.controller.setAutoStartEnabled(this.autoStartEnabled);
    this.controller.on('stateChange', this.stateChangeCallback);
    this.controller.on('controlEvent', this.controlEventCallback);
    this.phase = PlaybackPictureInPicturePhase.READY;
    this.syncControls();
  }

  private syncControls(): void {
    if (this.controller === undefined) {
      return;
    }
    try {
      this.controller.setPiPControlEnabled(
        PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        this.snapshot.hasCurrentTrack
      );
      this.controller.setPiPControlEnabled(
        PiPWindow.PiPControlType.VIDEO_PREVIOUS,
        this.snapshot.transportControlsEnabled
      );
      this.controller.setPiPControlEnabled(
        PiPWindow.PiPControlType.VIDEO_NEXT,
        this.snapshot.transportControlsEnabled
      );
      this.controller.updatePiPControlStatus(
        PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        this.snapshot.playing ?
          PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE
      );
    } catch (error) {
      console.warn(`Unable to synchronize PiP controls: ${PlaybackPictureInPicture.messageOf(error)}`);
    }
  }

  private static messageOf(error: Object): string {
    const businessError = error as BusinessError;
    return businessError.message === undefined ? `${error}` : businessError.message;
  }
}
