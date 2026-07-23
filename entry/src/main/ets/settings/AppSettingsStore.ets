import { SettingsRepository } from './SettingsRepository';
import { CompletedCollectionMode } from '../playback/model/PlaybackModels';
import { CompletedCollectionSettingPolicy } from './CompletedCollectionSettingPolicy';
import { DemoLibraryMode } from '../demo/DemoLibraryMode';

@Observed
export class AppSettingsStore {
  highQualityHeroArtwork: boolean = true;
  followPlaybackTheme: boolean = true;
  rememberPlaybackPosition: boolean = true;
  autoResumeAfterOutputReconnect: boolean = true;
  rememberLastTab: boolean = true;
  rememberLibrarySort: boolean = true;
  preserveShuffleOnManualPlay: boolean = false;
  autoRemoveUnavailableOnPlayback: boolean = false;
  completedCollectionMode: CompletedCollectionMode = CompletedCollectionMode.SMART;
  demoLibraryEnabled: boolean = false;

  private repository?: SettingsRepository;
  private initialized: boolean = false;

  initialize(repository: SettingsRepository): void {
    this.repository = repository;
    if (this.initialized) {
      return;
    }
    this.highQualityHeroArtwork = repository.getHighQualityHeroArtworkEnabled(true);
    this.followPlaybackTheme = repository.getFollowPlaybackThemeEnabled(true);
    this.rememberPlaybackPosition = repository.getRememberPlaybackPositionEnabled(true);
    this.autoResumeAfterOutputReconnect = repository.getAutoResumeAfterOutputReconnectEnabled(true);
    this.rememberLastTab = repository.getRememberLastTabEnabled(true);
    this.rememberLibrarySort = repository.getRememberLibrarySortEnabled(true);
    this.preserveShuffleOnManualPlay = repository.getPreserveShuffleOnManualPlayEnabled(false);
    this.autoRemoveUnavailableOnPlayback =
      repository.getAutoRemoveUnavailableOnPlaybackEnabled(false);
    this.completedCollectionMode = CompletedCollectionSettingPolicy.normalize(
      repository.getCompletedCollectionMode(CompletedCollectionMode.SMART)
    );
    this.demoLibraryEnabled = DemoLibraryMode.isAvailable() && repository.getDemoLibraryEnabled(false);
    DemoLibraryMode.setEnabled(this.demoLibraryEnabled);
    this.initialized = true;
  }

  setHighQualityHeroArtwork(value: boolean): void {
    this.highQualityHeroArtwork = value;
    this.repository?.setHighQualityHeroArtworkEnabled(value);
  }

  setFollowPlaybackTheme(value: boolean): void {
    this.followPlaybackTheme = value;
    this.repository?.setFollowPlaybackThemeEnabled(value);
  }

  setRememberPlaybackPosition(value: boolean): void {
    this.rememberPlaybackPosition = value;
    this.repository?.setRememberPlaybackPositionEnabled(value);
    if (!value) {
      const trackId = this.repository?.getPlaybackLastTrackId(-1) ?? -1;
      this.repository?.setPlaybackResumeState(trackId, 0);
    }
  }

  setAutoResumeAfterOutputReconnect(value: boolean): void {
    this.autoResumeAfterOutputReconnect = value;
    this.repository?.setAutoResumeAfterOutputReconnectEnabled(value);
  }

  setRememberLastTab(value: boolean): void {
    this.rememberLastTab = value;
    this.repository?.setRememberLastTabEnabled(value);
  }

  setRememberLibrarySort(value: boolean): void {
    this.rememberLibrarySort = value;
    this.repository?.setRememberLibrarySortEnabled(value);
    if (!value) {
      this.repository?.setSongSort(0, false);
      this.repository?.setAlbumSort(0, false);
    }
  }

  setPreserveShuffleOnManualPlay(value: boolean): void {
    this.preserveShuffleOnManualPlay = value;
    this.repository?.setPreserveShuffleOnManualPlayEnabled(value);
  }

  setAutoRemoveUnavailableOnPlayback(value: boolean): void {
    this.autoRemoveUnavailableOnPlayback = value;
    this.repository?.setAutoRemoveUnavailableOnPlaybackEnabled(value);
  }

  setCompletedCollectionMode(value: CompletedCollectionMode): void {
    this.completedCollectionMode = CompletedCollectionSettingPolicy.normalize(value);
    this.repository?.setCompletedCollectionMode(this.completedCollectionMode);
  }

  setDemoLibraryEnabled(value: boolean): void {
    this.demoLibraryEnabled = DemoLibraryMode.isAvailable() && value;
    this.repository?.setDemoLibraryEnabled(this.demoLibraryEnabled);
  }
}

export const appSettings: AppSettingsStore = new AppSettingsStore();
