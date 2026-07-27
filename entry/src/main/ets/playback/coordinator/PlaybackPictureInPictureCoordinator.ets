import { UIContext } from '@kit.ArkUI';
import { appSettings } from '../../settings/AppSettingsStore';
import { FloatingWindowSettingsPolicy } from '../../settings/FloatingWindowSettingsPolicy';
import {
  PlaybackPictureInPicture,
  PlaybackPictureInPictureCommands,
  PlaybackPictureInPictureSnapshot
} from '../pip/PlaybackPictureInPicture';

export class PlaybackPictureInPictureCoordinator {
  private readonly commands: PlaybackPictureInPictureCommands;
  private pictureInPicture: PlaybackPictureInPicture;
  private uiContext?: UIContext;
  private active: boolean = true;

  constructor(commands: PlaybackPictureInPictureCommands) {
    this.commands = commands;
    this.pictureInPicture = new PlaybackPictureInPicture(commands);
  }

  reopen(): void {
    if (this.active) {
      return;
    }
    this.pictureInPicture = new PlaybackPictureInPicture(this.commands);
    this.active = true;
  }

  async enter(uiContext: UIContext, snapshot: PlaybackPictureInPictureSnapshot): Promise<boolean> {
    if (!this.active) {
      return false;
    }
    const openBehavior = appSettings.floatingWindowOpenBehavior;
    await this.pictureInPicture.enter(
      uiContext,
      snapshot,
      FloatingWindowSettingsPolicy.shouldMinimizeAfterOpen(openBehavior)
    );
    return FloatingWindowSettingsPolicy.shouldClosePlayerPageAfterOpen(openBehavior);
  }

  bind(uiContext: UIContext, snapshot: PlaybackPictureInPictureSnapshot): void {
    if (!this.active) {
      return;
    }
    this.uiContext = uiContext;
    this.sync(snapshot);
  }

  unbind(): void {
    if (!this.active) {
      return;
    }
    this.uiContext = undefined;
    this.pictureInPicture.configureAutoStart(undefined, false).catch((error: Object): void => {
      console.warn(`Unable to disable automatic PiP: ${PlaybackPictureInPictureCoordinator.messageOf(error)}`);
    });
  }

  onForeground(): void {
    if (!this.active) {
      return;
    }
    if (FloatingWindowSettingsPolicy.shouldCloseOnForeground(
      appSettings.floatingWindowAutoCloseBehavior
    )) {
      this.stop('application foreground');
    }
  }

  onFullPlayerOpened(): void {
    if (!this.active) {
      return;
    }
    if (FloatingWindowSettingsPolicy.shouldCloseOnPlayerPageOpened(
      appSettings.floatingWindowAutoCloseBehavior
    )) {
      this.stop('full player opened');
    }
  }

  sync(snapshot: PlaybackPictureInPictureSnapshot): void {
    if (!this.active) {
      return;
    }
    this.pictureInPicture.sync(snapshot);
    const autoStartEnabled = FloatingWindowSettingsPolicy.shouldEnableAutoStart(
      appSettings.floatingWindowAutoStartOnMinimize,
      snapshot.hasCurrentTrack,
      snapshot.playing
    );
    this.pictureInPicture.configureAutoStart(this.uiContext, autoStartEnabled)
      .catch((error: Object): void => {
        console.warn(`Unable to configure automatic PiP: ${PlaybackPictureInPictureCoordinator.messageOf(error)}`);
      });
  }

  async dispose(): Promise<void> {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.uiContext = undefined;
    await this.pictureInPicture.dispose();
  }

  private stop(reason: string): void {
    this.pictureInPicture.stop().catch((error: Object): void => {
      console.warn(`Unable to stop PiP after ${reason}: ${PlaybackPictureInPictureCoordinator.messageOf(error)}`);
    });
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
