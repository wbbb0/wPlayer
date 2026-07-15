import { TrackListItem } from '../../library/model/LibraryModels';
import { playbackRuntime } from '../../playback/PlaybackRuntime';

@Builder
export function QueueActionMenu(items: Array<TrackListItem>) {
  Menu() {
    MenuItem({ content: '插播', labelInfo: '下一首开始' })
      .onClick(() => playbackRuntime.insertNext(items))
    MenuItem({ content: '追加到队列' })
      .onClick(() => playbackRuntime.appendToQueue(items))
  }
  .width(224)
}
