import { TrackListItem } from '../../library/model/LibraryModels';
import { playbackRuntime } from '../../playback/PlaybackRuntime';

export class QueueActionMenuParams {
  readonly items: Array<TrackListItem>;
  readonly onRequestAddToPlaylist: (items: Array<TrackListItem>) => void;

  constructor(
    items: Array<TrackListItem>,
    onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
      (_items: Array<TrackListItem>): void => {}
  ) {
    this.items = items;
    this.onRequestAddToPlaylist = onRequestAddToPlaylist;
  }
}

@Builder
export function QueueActionMenu(params: QueueActionMenuParams) {
  Menu() {
    MenuItem({ content: '插播', labelInfo: '下一首开始' })
      .onClick(() => playbackRuntime.insertNext(params.items))
    MenuItem({ content: '追加到队列' })
      .onClick(() => playbackRuntime.appendToQueue(params.items))
    MenuItem({ content: '添加到播放列表' })
      .onClick(() => params.onRequestAddToPlaylist(params.items))
  }
  .width(224)
}
