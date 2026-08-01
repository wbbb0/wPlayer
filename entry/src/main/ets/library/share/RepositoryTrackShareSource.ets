import { MusicRepository } from '../data/MusicRepository';
import {
  MusicFileShareTrack,
  TrackShareSource
} from './MusicFileSharePorts';

export class RepositoryTrackShareSource implements TrackShareSource {
  private readonly repository: MusicRepository;

  constructor(repository: MusicRepository) {
    this.repository = repository;
  }

  async getShareTrack(trackId: number): Promise<MusicFileShareTrack | undefined> {
    const detail = await this.repository.getTrackDetail(trackId);
    if (detail === undefined) {
      return undefined;
    }
    return {
      uri: detail.uri,
      title: detail.title,
      displayName: detail.displayName,
      artistDisplay: detail.artistDisplay
    };
  }
}
