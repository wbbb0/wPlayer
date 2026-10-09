import { PlaybackTrack } from '../model/PlaybackModels';

/** Current reads and prefetches share the same authorization-before-I/O contract. */
export class PlaybackLyricsReader {
  private readonly activate: (uri: string) => Promise<boolean>;
  private readonly readSource: (track: PlaybackTrack) => Promise<string>;

  constructor(activate: (uri: string) => Promise<boolean>, readSource: (track: PlaybackTrack) => Promise<string>) {
    this.activate = activate;
    this.readSource = readSource;
  }

  async read(track: PlaybackTrack): Promise<string> {
    if (!await this.activate(track.uri)) {
      throw new Error('音乐文件读取授权已失效');
    }
    return this.readSource(track);
  }
}
