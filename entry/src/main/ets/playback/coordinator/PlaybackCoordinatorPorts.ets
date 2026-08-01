import { image } from '@kit.ImageKit';
import { MusicRepository } from '../../library/data/MusicRepository';
import {
  PersistedPlaybackQueueItem as RepositoryPlaybackQueueItem,
  PersistedPlaybackQueueSnapshot as RepositoryPlaybackQueueSnapshot
} from '../../library/data/MusicRepositoryTypes';
import { SettingsRepository } from '../../settings/SettingsRepository';
import { DecodedFullArtwork } from '../artwork/ArtworkMemoryCache';
import { PlaybackTrack, QueueTrack } from '../model/PlaybackModels';
import { PlaybackMediaHost } from './PlaybackMediaCoordinator';
import {
  PersistedPlaybackQueueSnapshot,
  PlaybackPersistenceSettings,
  PlaybackRestoreRepository
} from './PlaybackPersistenceCoordinator';

export class PlaybackPersistencePort implements PlaybackPersistenceSettings, PlaybackRestoreRepository {
  private readonly repository: MusicRepository;
  private readonly settingsProvider: () => SettingsRepository | undefined;

  constructor(repository: MusicRepository, settingsProvider: () => SettingsRepository | undefined) {
    this.repository = repository;
    this.settingsProvider = settingsProvider;
  }

  getPlaybackLastTrackId(defaultValue: number = -1): number {
    return this.settingsProvider()?.getPlaybackLastTrackId(defaultValue) ?? defaultValue;
  }

  getPlaybackLastPositionMs(defaultValue: number = 0): number {
    return this.settingsProvider()?.getPlaybackLastPositionMs(defaultValue) ?? defaultValue;
  }

  getPlaybackQueueTrackIds(): Array<number> {
    return this.settingsProvider()?.getPlaybackQueueTrackIds() ?? [];
  }

  getPlaybackQueueCurrentTrackId(defaultValue: number = -1): number {
    return this.settingsProvider()?.getPlaybackQueueCurrentTrackId(defaultValue) ?? defaultValue;
  }

  setPlaybackResumeState(trackId: number, positionMs: number): void {
    this.settingsProvider()?.setPlaybackResumeState(trackId, positionMs);
  }

  clearLegacyPlaybackQueue(): void {
    this.settingsProvider()?.clearLegacyPlaybackQueue();
  }

  getPlaybackQueueTracks(trackIds: Array<number>): Promise<Array<QueueTrack>> {
    return this.repository.getPlaybackQueueTracks(trackIds);
  }

  getPersistedPlaybackQueue(): Promise<PersistedPlaybackQueueSnapshot | undefined> {
    return this.repository.getPersistedPlaybackQueue();
  }

  replacePersistedPlaybackQueue(snapshot: PersistedPlaybackQueueSnapshot): Promise<void> {
    const repositorySnapshot: RepositoryPlaybackQueueSnapshot = {
      items: snapshot.items.map((item): RepositoryPlaybackQueueItem => ({
        position: item.position,
        playbackPosition: item.playbackPosition,
        trackId: item.trackId
      })),
      currentPosition: snapshot.currentPosition,
      shuffleEnabled: snapshot.shuffleEnabled
    };
    return this.repository.replacePersistedPlaybackQueue(repositorySnapshot);
  }

  updatePersistedPlaybackQueuePosition(currentPosition: number): Promise<void> {
    return this.repository.updatePersistedPlaybackQueuePosition(currentPosition);
  }
}

export class PlaybackMediaHostAdapter implements PlaybackMediaHost {
  private readonly isCurrent: (token: number) => boolean;
  private readonly heroCommit: (pixelMap: image.PixelMap) => void;
  private readonly fullCommit: (artwork: DecodedFullArtwork) => void;
  private readonly lyricsCommit: (track: PlaybackTrack, lyrics: string) => void;
  private readonly lyricsClear: () => void;
  private readonly paletteCommit: (track: QueueTrack) => void;

  constructor(isCurrent: (token: number) => boolean,
    heroCommit: (pixelMap: image.PixelMap) => void,
    fullCommit: (artwork: DecodedFullArtwork) => void,
    lyricsCommit: (track: PlaybackTrack, lyrics: string) => void,
    lyricsClear: () => void,
    paletteCommit: (track: QueueTrack) => void) {
    this.isCurrent = isCurrent;
    this.heroCommit = heroCommit;
    this.fullCommit = fullCommit;
    this.lyricsCommit = lyricsCommit;
    this.lyricsClear = lyricsClear;
    this.paletteCommit = paletteCommit;
  }

  isTrackRequestCurrent(token: number): boolean {
    return this.isCurrent(token);
  }

  commitHeroArtwork(pixelMap: image.PixelMap): void {
    this.heroCommit(pixelMap);
  }

  commitFullArtwork(artwork: DecodedFullArtwork): void {
    this.fullCommit(artwork);
  }

  commitLyrics(track: PlaybackTrack, lyrics: string): void {
    this.lyricsCommit(track, lyrics);
  }

  clearLyricsAfterFailure(): void {
    this.lyricsClear();
  }

  commitRefreshedPalette(track: QueueTrack): void {
    this.paletteCommit(track);
  }
}
