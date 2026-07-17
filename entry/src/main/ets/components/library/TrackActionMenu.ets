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

export class TrackActionMenuParams {
  readonly queueItems: Array<TrackListItem>;
  readonly linkActions: Array<LibraryLinkAction>;
  readonly onNavigate: (target: LibraryNavigationTarget) => void;

  constructor(
    queueItems: Array<TrackListItem>,
    linkActions: Array<LibraryLinkAction>,
    onNavigate: (target: LibraryNavigationTarget) => void
  ) {
    this.queueItems = queueItems;
    this.linkActions = linkActions;
    this.onNavigate = onNavigate;
  }
}

@Builder
export function TrackActionMenu(params: TrackActionMenuParams) {
  Menu() {
    if (params.queueItems.length > 0) {
      MenuItem({ content: '插播', labelInfo: '下一首开始' })
        .onClick(() => playbackRuntime.insertNext(params.queueItems))
      MenuItem({ content: '追加到队列' })
        .onClick(() => playbackRuntime.appendToQueue(params.queueItems))
    }
    ForEach(params.linkActions, (action: LibraryLinkAction) => {
      MenuItem({
        content: action.label,
        labelInfo: libraryLinkRoleLabel(action.role)
      })
        .onClick(() => params.onNavigate(action.target))
    }, (action: LibraryLinkAction) =>
      `${action.target.identity.kind}:${action.target.identity.id}`)
    if (params.queueItems.length === 0 && params.linkActions.length === 0) {
      MenuItem({ content: '没有可前往的内容' })
        .enabled(false)
    }
  }
  .width(260)
}

export class TrackActionMenuPresenter {
  static async open(
    uiContext: UIContext,
    store: LibraryStore,
    trackId: number,
    anchorId: string,
    queueItems: Array<TrackListItem>,
    current: LibraryEntityIdentity | undefined,
    onNavigate: (target: LibraryNavigationTarget) => void
  ): Promise<void> {
    try {
      const targets = await store.getTrackNavigationTargets(trackId);
      const actions = targets === undefined ? [] : libraryLinkActions(targets, current);
      const content = new ComponentContent(
        uiContext,
        wrapBuilder(TrackActionMenu),
        new TrackActionMenuParams(queueItems, actions, onNavigate)
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
