import { SymbolGlyphModifier } from '@kit.ArkUI';
import {
  MenuSectionDivider
} from '../library/MenuActionGroups';

export class PlayerQueueSelectionMenuParams {
  readonly onPlay: () => void;
  readonly onInsertNext: () => void;
  readonly onAppendToQueue: () => void;
  readonly onAddToPlaylist: () => void;
  readonly onRemoveFromQueue: () => void;

  constructor(
    onPlay: () => void,
    onInsertNext: () => void,
    onAppendToQueue: () => void,
    onAddToPlaylist: () => void,
    onRemoveFromQueue: () => void
  ) {
    this.onPlay = onPlay;
    this.onInsertNext = onInsertNext;
    this.onAppendToQueue = onAppendToQueue;
    this.onAddToPlaylist = onAddToPlaylist;
    this.onRemoveFromQueue = onRemoveFromQueue;
  }
}

@Builder
export function PlayerQueueSelectionMenu(params: PlayerQueueSelectionMenuParams) {
  Menu() {
    MenuItem({ content: '播放' })
      .onClick(params.onPlay)
    MenuItem({ content: '插播', labelInfo: '下一首开始' })
      .onClick(params.onInsertNext)
    MenuItem({ content: '追加到播放队列' })
      .onClick(params.onAppendToQueue)
    MenuSectionDivider()
    MenuItem({ content: '添加到播放列表' })
      .onClick(params.onAddToPlaylist)
    MenuSectionDivider()
    MenuItem({ content: '从播放队列移除' })
      .onClick(params.onRemoveFromQueue)
  }
  .width(240)
}

export class CurrentTrackActionMenuParams {
  readonly trackAvailable: boolean;
  readonly completedCollectionEnabled: boolean;
  readonly onInsertNext: () => void;
  readonly onAppendToQueue: () => void;
  readonly onAddToPlaylist: () => void;
  readonly onOpenDetails: () => void;
  readonly onCompletedCollectionChange: (enabled: boolean) => void;

  constructor(
    trackAvailable: boolean,
    completedCollectionEnabled: boolean,
    onInsertNext: () => void,
    onAppendToQueue: () => void,
    onAddToPlaylist: () => void,
    onOpenDetails: () => void,
    onCompletedCollectionChange: (enabled: boolean) => void
  ) {
    this.trackAvailable = trackAvailable;
    this.completedCollectionEnabled = completedCollectionEnabled;
    this.onInsertNext = onInsertNext;
    this.onAppendToQueue = onAppendToQueue;
    this.onAddToPlaylist = onAddToPlaylist;
    this.onOpenDetails = onOpenDetails;
    this.onCompletedCollectionChange = onCompletedCollectionChange;
  }
}

@Builder
export function CurrentTrackActionMenu(params: CurrentTrackActionMenuParams) {
  Menu() {
    MenuItem({ content: '插播', labelInfo: '下一首开始' })
      .enabled(params.trackAvailable)
      .onClick(params.onInsertNext)
    MenuItem({ content: '追加到队列' })
      .enabled(params.trackAvailable)
      .onClick(params.onAppendToQueue)
    MenuSectionDivider()
    MenuItem({ content: '添加到播放列表' })
      .enabled(params.trackAvailable)
      .onClick(params.onAddToPlaylist)
    MenuSectionDivider()
    MenuItem({ content: '文件信息' })
      .enabled(params.trackAvailable)
      .onClick(params.onOpenDetails)
    MenuSectionDivider()
    MenuItem({
      content: '收集完整听过的音乐',
      symbolEndIcon: params.completedCollectionEnabled ?
        new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
    })
      .onClick(() => params.onCompletedCollectionChange(!params.completedCollectionEnabled))
  }
  .width(260)
}
