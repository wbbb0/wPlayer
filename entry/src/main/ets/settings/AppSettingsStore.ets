import { SettingsRepository } from './SettingsRepository';

@Observed
export class AppSettingsStore {
  highQualityHeroArtwork: boolean = true;
  followPlaybackTheme: boolean = true;
  rememberPlaybackPosition: boolean = true;
  rememberLastTab: boolean = true;
  rememberLibrarySort: boolean = true;
  preserveShuffleOnManualPlay: boolean = false;

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
    this.rememberLastTab = repository.getRememberLastTabEnabled(true);
    this.rememberLibrarySort = repository.getRememberLibrarySortEnabled(true);
    this.preserveShuffleOnManualPlay = repository.getPreserveShuffleOnManualPlayEnabled(false);
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
}

export const appSettings: AppSettingsStore = new AppSettingsStore();
