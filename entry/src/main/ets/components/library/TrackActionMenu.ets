import { BusinessError } from '@kit.BasicServicesKit';
import { ComponentContent, UIContext } from '@kit.ArkUI';
import {
  LibraryEntityIdentity,
  LibraryNavigationTarget,
  TrackListItem
} from '../../library/model/LibraryModels';
import { LibraryStore } from '../../library/store/LibraryStore';
import { playbackRuntime } from '../../playback/PlaybackRuntime';
import {
  LibraryLinkAction,
  libraryLinkActions,
  libraryLinkRoleLabel
} from '../navigation/LibraryNavigation';
import {
  MenuSectionDivider
} from './MenuActionGroups';

export class TrackActionMenuParams {
  readonly queueItems: Array<TrackListItem>;
  readonly linkActions: Array<LibraryLinkAction>;
  readonly onNavigate: (target: LibraryNavigationTarget) => void;
  readonly onRequestAddToPlaylist: (items: Array<TrackListItem>) => void;
  readonly removeLabel: string;
  readonly onRemove?: () => void;
  readonly onOpenDetails?: (track: TrackListItem) => void;
  readonly onShareFile?: () => void;

  constructor(options: TrackActionMenuOptions) {
    this.queueItems = options.queueItems;
    this.linkActions = options.linkActions;
    this.onNavigate = options.onNavigate;
    this.onRequestAddToPlaylist = options.onRequestAddToPlaylist;
    this.removeLabel = options.removeLabel;
    this.onRemove = options.onRemove;
    this.onOpenDetails = options.onOpenDetails;
    this.onShareFile = options.onShareFile;
  }
}

export interface TrackActionMenuOptions {
  queueItems: Array<TrackListItem>;
  linkActions: Array<LibraryLinkAction>;
  onNavigate: (target: LibraryNavigationTarget) => void;
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void;
  removeLabel: string;
  onRemove?: () => void;
  onOpenDetails?: (track: TrackListItem) => void;
  onShareFile?: () => void;
}

@Builder
export function TrackActionMenu(params: TrackActionMenuParams) {
  Menu() {
    if (params.queueItems.length > 0) {
      MenuItem({ content: '插播', labelInfo: '下一首开始' })
        .onClick(() => playbackRuntime.insertNext(params.queueItems))
      MenuItem({ content: '追加到队列' })
        .onClick(() => playbackRuntime.appendToQueue(params.queueItems))
      MenuSectionDivider()
      MenuItem({ content: '添加到播放列表' })
        .onClick(() => params.onRequestAddToPlaylist(params.queueItems))
    }
    if (params.linkActions.length > 0) {
      if (params.queueItems.length > 0) {
        MenuSectionDivider()
      }
      ForEach(params.linkActions, (action: LibraryLinkAction) => {
        MenuItem({
          content: action.label,
          labelInfo: libraryLinkRoleLabel(action.role)
        })
          .onClick(() => params.onNavigate(action.target))
      }, (action: LibraryLinkAction) =>
        `${action.target.identity.kind}:${action.target.identity.id}`)
    }
    if (params.queueItems.length === 1 && params.onOpenDetails !== undefined) {
      if (params.queueItems.length > 0 || params.linkActions.length > 0) {
        MenuSectionDivider()
      }
      MenuItem({ content: '文件信息' })
        .onClick(() => params.onOpenDetails?.(params.queueItems[0]))
    }
    if (params.queueItems.length === 1 && params.onShareFile !== undefined) {
      if (params.onOpenDetails === undefined) {
        MenuSectionDivider()
      }
      MenuItem({ content: '分享音乐文件' })
        .onClick(params.onShareFile)
    }
    if (params.onRemove !== undefined && params.removeLabel.length > 0) {
      if (params.queueItems.length > 0 || params.linkActions.length > 0 ||
        (params.queueItems.length === 1 && params.onOpenDetails !== undefined)) {
        MenuSectionDivider()
      }
      MenuItem({ content: params.removeLabel })
        .onClick(() => params.onRemove?.())
    }
    if (params.queueItems.length === 0 && params.linkActions.length === 0 &&
      (params.onRemove === undefined || params.removeLabel.length === 0)) {
      MenuItem({ content: '没有可前往的内容' })
        .enabled(false)
    }
  }
  .width(260)
}

export interface TrackActionMenuOpenOptions {
  queueItems: Array<TrackListItem>;
  current?: LibraryEntityIdentity;
  onNavigate: (target: LibraryNavigationTarget) => void;
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void;
  onShareTrackFile: (trackId: number) => void;
  removeLabel: string;
  onRemove?: () => void;
  onOpenDetails?: (track: TrackListItem) => void;
}

export class TrackActionMenuPresenter {
  static async open(
    uiContext: UIContext,
    store: LibraryStore,
    trackId: number,
    anchorId: string,
    options: TrackActionMenuOpenOptions
  ): Promise<void> {
    try {
      const targets = await store.getTrackNavigationTargets(trackId);
      const actions = targets === undefined ? [] : libraryLinkActions(targets, options.current);
      const content = new ComponentContent(
        uiContext,
        wrapBuilder(TrackActionMenu),
        new TrackActionMenuParams({
          queueItems: options.queueItems,
          linkActions: actions,
          onNavigate: options.onNavigate,
          onRequestAddToPlaylist: options.onRequestAddToPlaylist,
          removeLabel: options.removeLabel,
          onRemove: options.onRemove,
          onOpenDetails: options.onOpenDetails,
          onShareFile: (): void => options.onShareTrackFile(trackId)
        })
      );
      await uiContext.getPromptAction().openMenu(
        content,
        { id: anchorId },
        {
          placement: Placement.BottomRight,
          enableArrow: true
        }
      );
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to open track action menu: ${businessError.code}, ${businessError.message}`);
    }
  }
}
