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
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { BundledArtworkCatalog } from '../../library/artwork/BundledArtworkCatalog';
import {
  PlaybackPictureInPicturePolicy,
  PlaybackPictureInPictureSize
} from './PlaybackPictureInPicturePolicy';
import { PlaybackPictureInPictureLifecycle } from './PlaybackPictureInPictureLifecycle';

const PIP_OPERATION_CANCELLED: Error = new Error('画中画启动已取消');

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
  private readonly lifecycle: PlaybackPictureInPictureLifecycle =
    new PlaybackPictureInPictureLifecycle();
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
  private disposePromise?: Promise<void>;
  private stopWhenStarted: boolean = false;
  private autoStartEnabled: boolean = false;
  private stateChangeCallback?: (state: PiPWindow.PiPState, reason: string) => void;
  private controlEventCallback?: (event: PiPWindow.ControlEventParam) => void;

  constructor(commands: PlaybackPictureInPictureCommands) {
    this.commands = commands;
  }

  enter(uiContext: UIContext, snapshot: PlaybackPictureInPictureSnapshot,
    autoMinimizeApp: boolean): Promise<void> {
    if (!this.lifecycle.canStartOperation()) {
      return Promise.reject(PIP_OPERATION_CANCELLED);
    }
    this.sync(snapshot);
    if (!snapshot.hasCurrentTrack) {
      return Promise.reject(new Error('请先选择一首音乐'));
    }
    if (!PiPWindow.isPiPEnabled()) {
      return Promise.reject(new Error('当前设备未开启画中画功能'));
    }
    if (this.enterPromise !== undefined) {
      return this.enterPromise;
    }
    const epoch = this.lifecycle.current();
    if (this.phase === PlaybackPictureInPicturePhase.STARTED ||
      this.phase === PlaybackPictureInPicturePhase.STARTING) {
      const controller = this.controller;
      if (!autoMinimizeApp || controller === undefined) {
        return Promise.resolve();
      }
      return this.trackEnterOperation(
        this.minimizeHostApplication(uiContext, epoch, controller),
        epoch
      );
    }
    return this.trackEnterOperation(this.enterInternal(uiContext, autoMinimizeApp, epoch), epoch);
  }

  private trackEnterOperation(operation: Promise<void>, epoch: number): Promise<void> {
    this.enterPromise = operation.finally((): void => {
      if (this.lifecycle.isCurrent(epoch)) {
        this.enterPromise = undefined;
      }
    });
    return this.enterPromise;
  }

  async configureAutoStart(uiContext: UIContext | undefined, enabled: boolean): Promise<void> {
    const changed = enabled !== this.autoStartEnabled;
    this.autoStartEnabled = enabled;
    if (!this.lifecycle.canStartOperation()) {
      return;
    }
    if (this.controller !== undefined) {
      if (changed) {
        this.controller.setAutoStartEnabled(enabled);
      }
      return;
    }
    if (!enabled || uiContext === undefined) {
      return;
    }
    const epoch = this.lifecycle.current();
    await this.ensureController(uiContext, epoch);
    this.ensureCurrent(epoch);
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
    if (!this.lifecycle.canStartOperation()) {
      return;
    }
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
    if (this.disposePromise !== undefined) {
      return this.disposePromise;
    }
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
      const epoch = this.lifecycle.current();
      this.stopPromise = this.controller.stopPiP().finally((): void => {
        if (this.lifecycle.isCurrent(epoch)) {
          this.stopPromise = undefined;
        }
      });
    } catch (error) {
      return Promise.reject(error);
    }
    return this.stopPromise;
  }

  dispose(): Promise<void> {
    if (this.disposePromise !== undefined) {
      return this.disposePromise;
    }
    const pendingCreation = this.creationPromise;
    const pendingEnter = this.enterPromise;
    const pendingStop = this.stopPromise;
    const phaseAtDispose = this.phase;
    const controllerAtDispose = this.controller;
    this.lifecycle.beginDispose();
    this.disableAutoStartForDisposal(controllerAtDispose);
    this.disposePromise = this.lifecycle.runDisposal(
      pendingCreation,
      pendingEnter,
      pendingStop,
      (pendingStopSucceeded: boolean): Promise<void> =>
        this.disposeController(pendingStopSucceeded, phaseAtDispose)
    ).finally((): void => {
      this.disposePromise = undefined;
      this.lifecycle.finishDispose();
    });
    return this.disposePromise;
  }

  private async disposeController(pendingStopSucceeded: boolean,
    phaseAtDispose: PlaybackPictureInPicturePhase): Promise<void> {
    const controller = this.controller;
    const controlEventCallback = this.controlEventCallback;
    this.creationPromise = undefined;
    this.enterPromise = undefined;
    this.stopPromise = undefined;
    this.stopWhenStarted = false;
    if (controller !== undefined) {
      try {
        controller.off('stateChange');
      } catch (error) {
        console.warn(`Unable to detach PiP state callback: ${PlaybackPictureInPicture.messageOf(error)}`);
      }
      if (controlEventCallback !== undefined) {
        try {
          controller.off('controlEvent', controlEventCallback);
        } catch (error) {
          console.warn(`Unable to detach PiP control callback: ${PlaybackPictureInPicture.messageOf(error)}`);
        }
      }
      if (!pendingStopSucceeded &&
        (phaseAtDispose === PlaybackPictureInPicturePhase.STARTED ||
          phaseAtDispose === PlaybackPictureInPicturePhase.STARTING ||
          phaseAtDispose === PlaybackPictureInPicturePhase.STOPPING)) {
        try {
          await controller.stopPiP();
        } catch (error) {
          console.warn(`Unable to stop PiP: ${PlaybackPictureInPicture.messageOf(error)}`);
        }
      }
    }
    this.artworkController.dispose();
    this.controller = undefined;
    this.contentNode = null;
    this.stateChangeCallback = undefined;
    this.controlEventCallback = undefined;
    this.phase = PlaybackPictureInPicturePhase.IDLE;
  }

  private disableAutoStartForDisposal(controller: PiPWindow.PiPController | undefined): void {
    if (controller === undefined) {
      return;
    }
    try {
      controller.setAutoStartEnabled(false);
    } catch (error) {
      console.warn(`Unable to disable automatic PiP during disposal: ${
        PlaybackPictureInPicture.messageOf(error)
      }`);
    }
  }

  private async enterInternal(uiContext: UIContext, autoMinimizeApp: boolean,
    epoch: number): Promise<void> {
    let controller: PiPWindow.PiPController | undefined;
    try {
      await this.ensureController(uiContext, epoch);
      this.ensureCurrent(epoch);
      controller = this.controller;
      if (controller === undefined) {
        throw new Error('画中画控制器不可用');
      }
      this.phase = PlaybackPictureInPicturePhase.STARTING;
      await controller.startPiP();
      this.ensureOwnedController(epoch, controller);
    } catch (error) {
      if (error === PIP_OPERATION_CANCELLED || !this.lifecycle.isCurrent(epoch)) {
        throw PIP_OPERATION_CANCELLED;
      }
      if (this.phase !== PlaybackPictureInPicturePhase.STARTED) {
        this.phase = this.controller === undefined ?
          PlaybackPictureInPicturePhase.IDLE : PlaybackPictureInPicturePhase.READY;
      }
      const businessError = error as BusinessError;
      const code = businessError.code === undefined ? '' : `（${businessError.code}）`;
      throw new Error(`无法启动画中画${code}`);
    }
    if (autoMinimizeApp) {
      await this.minimizeHostApplication(uiContext, epoch, controller);
    }
  }

  private async minimizeHostApplication(uiContext: UIContext, epoch?: number,
    controller?: PiPWindow.PiPController): Promise<void> {
    if (epoch !== undefined && controller !== undefined) {
      this.ensureOwnedController(epoch, controller);
    }
    const context = uiContext.getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      throw new Error('画中画已启动，但无法获取主窗口上下文');
    }
    try {
      const mainWindow = await window.getLastWindow(context);
      if (epoch !== undefined && controller !== undefined) {
        this.ensureOwnedController(epoch, controller);
      }
      await mainWindow.minimize();
      if (epoch !== undefined && controller !== undefined) {
        this.ensureOwnedController(epoch, controller);
      }
      return;
    } catch (error) {
      if (error === PIP_OPERATION_CANCELLED) {
        throw PIP_OPERATION_CANCELLED;
      }
      const businessError = error as BusinessError;
      if (businessError.code !== 801) {
        const code = businessError.code === undefined ? '' : `（${businessError.code}）`;
        throw new Error(`画中画已启动，但主窗口无法最小化${code}`);
      }
    }
    try {
      if (epoch !== undefined && controller !== undefined) {
        this.ensureOwnedController(epoch, controller);
      }
      if (deviceInfo.deviceType === deviceInfo.DeviceTypes.TYPE_2IN1) {
        throw new Error('当前设备不支持将应用退至后台');
      }
      if (canIUse('SystemCapability.Ability.AbilityRuntime.Core')) {
        await context.moveAbilityToBackground();
        if (epoch !== undefined && controller !== undefined) {
          this.ensureOwnedController(epoch, controller);
        }
      } else {
        throw new Error('当前设备不支持将应用退至后台');
      }
    } catch (error) {
      if (error === PIP_OPERATION_CANCELLED) {
        throw PIP_OPERATION_CANCELLED;
      }
      const businessError = error as BusinessError;
      const code = businessError.code === undefined ? '' : `（${businessError.code}）`;
      throw new Error(`画中画已启动，但主窗口无法退至后台${code}`);
    }
  }

  private ensureController(uiContext: UIContext, epoch: number): Promise<void> {
    if (!this.lifecycle.canStartOperation()) {
      return Promise.reject(PIP_OPERATION_CANCELLED);
    }
    if (this.controller !== undefined) {
      return Promise.resolve();
    }
    if (this.creationPromise !== undefined) {
      return this.creationPromise;
    }
    this.creationPromise = this.createController(uiContext, epoch).finally((): void => {
      if (this.lifecycle.isCurrent(epoch)) {
        this.creationPromise = undefined;
      }
    });
    return this.creationPromise;
  }

  private async createController(uiContext: UIContext, epoch: number): Promise<void> {
    this.ensureCurrent(epoch);
    const context = uiContext.getHostContext();
    if (context === undefined) {
      throw new Error('无法获取主窗口上下文');
    }
    this.phase = PlaybackPictureInPicturePhase.CREATING;
    this.artworkController.update(this.snapshot.artworkUri);
    const contentNode = typeNode.createNode(uiContext, 'XComponent', {
      type: XComponentType.SURFACE,
      controller: this.xComponentController
    });
    this.contentNode = contentNode;
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
    let controller: PiPWindow.PiPController;
    try {
      controller = await PiPWindow.create(config, contentNode);
    } catch (error) {
      if (!this.lifecycle.isCurrent(epoch)) {
        throw PIP_OPERATION_CANCELLED;
      }
      this.phase = PlaybackPictureInPicturePhase.IDLE;
      this.contentNode = null;
      throw new Error(PlaybackPictureInPicture.messageOf(error));
    }
    this.ensureCurrent(epoch);
    this.controller = controller;
    this.registerControllerCallbacks(controller, epoch);
    controller.setAutoStartEnabled(this.autoStartEnabled);
    this.phase = PlaybackPictureInPicturePhase.READY;
    this.syncControls();
  }

  private registerControllerCallbacks(controller: PiPWindow.PiPController, epoch: number): void {
    const stateChangeCallback =
      (state: PiPWindow.PiPState, _reason: string): void => {
        if (!this.lifecycle.ownsController(epoch, controller, this.controller)) {
          return;
        }
        this.handleStateChange(state);
      };
    const controlEventCallback =
      (event: PiPWindow.ControlEventParam): void => {
        if (!this.lifecycle.ownsController(epoch, controller, this.controller)) {
          return;
        }
        this.handleControlEvent(event);
      };
    this.stateChangeCallback = stateChangeCallback;
    this.controlEventCallback = controlEventCallback;
    controller.on('stateChange', stateChangeCallback);
    controller.on('controlEvent', controlEventCallback);
  }

  private handleStateChange(state: PiPWindow.PiPState): void {
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
  }

  private handleControlEvent(event: PiPWindow.ControlEventParam): void {
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

  private ensureCurrent(epoch: number): void {
    if (!this.lifecycle.isCurrent(epoch)) {
      throw PIP_OPERATION_CANCELLED;
    }
  }

  private ensureOwnedController(epoch: number, controller: PiPWindow.PiPController): void {
    if (!this.lifecycle.ownsController(epoch, controller, this.controller)) {
      throw PIP_OPERATION_CANCELLED;
    }
  }

  private static messageOf(error: Object): string {
    const businessError = error as BusinessError;
    return businessError.message === undefined ? `${error}` : businessError.message;
  }
}
