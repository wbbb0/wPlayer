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
  readonly onRequestAddToPlaylist: (items: Array<TrackListItem>) => void;
  readonly removeLabel: string;
  readonly onRemove?: () => void;
  readonly onOpenDetails?: (track: TrackListItem) => void;

  constructor(
    queueItems: Array<TrackListItem>,
    linkActions: Array<LibraryLinkAction>,
    onNavigate: (target: LibraryNavigationTarget) => void,
    onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
      (_items: Array<TrackListItem>): void => {},
    removeLabel: string = '',
    onRemove?: () => void,
    onOpenDetails?: (track: TrackListItem) => void
  ) {
    this.queueItems = queueItems;
    this.linkActions = linkActions;
    this.onNavigate = onNavigate;
    this.onRequestAddToPlaylist = onRequestAddToPlaylist;
    this.removeLabel = removeLabel;
    this.onRemove = onRemove;
    this.onOpenDetails = onOpenDetails;
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
      MenuItem({ content: '添加到播放列表' })
        .onClick(() => params.onRequestAddToPlaylist(params.queueItems))
    }
    ForEach(params.linkActions, (action: LibraryLinkAction) => {
      MenuItem({
        content: action.label,
        labelInfo: libraryLinkRoleLabel(action.role)
      })
        .onClick(() => params.onNavigate(action.target))
    }, (action: LibraryLinkAction) =>
      `${action.target.identity.kind}:${action.target.identity.id}`)
    if (params.queueItems.length === 1 && params.onOpenDetails !== undefined) {
      MenuItem({ content: '歌曲信息' })
        .onClick(() => params.onOpenDetails?.(params.queueItems[0]))
    }
    if (params.onRemove !== undefined && params.removeLabel.length > 0) {
      MenuItem({ content: params.removeLabel })
        .onClick(() => params.onRemove?.())
    }
    if (params.queueItems.length === 0 && params.linkActions.length === 0 &&
      params.onRemove === undefined) {
      MenuItem({ content: '没有可前往的内容' })
        .enabled(false)
    }
  }
  .width(260)
}

@Component
export struct TrackContextMenu {
  @ObjectLink store: LibraryStore;
  @Prop track: TrackListItem;
  @Prop current: LibraryEntityIdentity | undefined = undefined;
  @State linkActions: Array<LibraryLinkAction> = [];
  onNavigate: (target: LibraryNavigationTarget) => void =
    (_target: LibraryNavigationTarget): void => {};
  onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
    (_items: Array<TrackListItem>): void => {};
  @Prop removeLabel: string = '';
  onRemove: (() => void) | undefined = undefined;
  onOpenDetails: ((track: TrackListItem) => void) | undefined = undefined;
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.loadLinkActions();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private async loadLinkActions(): Promise<void> {
    try {
      const targets = await this.store.getTrackNavigationTargets(this.track.id);
      if (this.active) {
        this.linkActions = targets === undefined ? [] : libraryLinkActions(targets, this.current);
      }
    } catch (error) {
      if (this.active) {
        this.linkActions = [];
      }
      console.warn(`Unable to load track context actions: ${error instanceof Error ? error.message : `${error}`}`);
    }
  }

  build() {
    TrackActionMenu(new TrackActionMenuParams(
      [this.track],
      this.linkActions,
      this.onNavigate,
      this.onRequestAddToPlaylist,
      this.removeLabel,
      this.onRemove,
      this.onOpenDetails
    ))
  }
}

export class TrackActionMenuPresenter {
  static async open(
    uiContext: UIContext,
    store: LibraryStore,
    trackId: number,
    anchorId: string,
    queueItems: Array<TrackListItem>,
    current: LibraryEntityIdentity | undefined,
    onNavigate: (target: LibraryNavigationTarget) => void,
    onRequestAddToPlaylist: (items: Array<TrackListItem>) => void =
      (_items: Array<TrackListItem>): void => {},
    removeLabel: string = '',
    onRemove?: () => void,
    onOpenDetails?: (track: TrackListItem) => void
  ): Promise<void> {
    try {
      const targets = await store.getTrackNavigationTargets(trackId);
      const actions = targets === undefined ? [] : libraryLinkActions(targets, current);
      const content = new ComponentContent(
        uiContext,
        wrapBuilder(TrackActionMenu),
        new TrackActionMenuParams(
          queueItems,
          actions,
          onNavigate,
          onRequestAddToPlaylist,
          removeLabel,
          onRemove,
          onOpenDetails
        )
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
