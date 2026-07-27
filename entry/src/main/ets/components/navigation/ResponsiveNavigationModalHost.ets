import { LibraryStore } from '../../library/store/LibraryStore';
import {
  TrackArtworkViewerState,
  TrackDetailState
} from '../../library/store/LibraryDetailState';
import { TrackDetail } from '../../library/model/LibraryModels';
import { TrackDetailPage } from '../../pages/library/TrackDetailPage';
import { TrackArtworkViewer } from '../../pages/library/TrackArtworkViewer';
import { AppShellLayoutSpec } from '../layout/AppShellLayoutSpec';

const TRACK_DETAIL_SHEET_MAX_WIDTH: number = 840;
const TRACK_DETAIL_SHEET_MIN_MARGIN: number = 96;

@Observed
export class TrackDetailSheetPresentationState {
  trackId: number = 0;
  title: string = '';
  state: TrackDetailState | undefined = undefined;
  scroller: Scroller = new Scroller();

  present(trackId: number, title: string): void {
    this.trackId = trackId;
    this.title = title;
    this.state = new TrackDetailState(trackId);
    this.scroller = new Scroller();
  }

  clear(): void {
    this.state = undefined;
  }
}

@Component
export struct ResponsiveNavigationModalHost {
  @ObjectLink libraryStore: LibraryStore;
  @Link trackDetailVisible: boolean;
  @Link artworkViewerVisible: boolean;
  @Link playlistImportVisible: boolean;
  @ObjectLink trackDetailState: TrackDetailSheetPresentationState;
  @Prop artworkViewerState: TrackArtworkViewerState | undefined = undefined;
  @Prop topInset: number = 0;
  @Prop bottomInset: number = 0;
  @Prop rootWidth: number = 0;
  @Prop themePageBackground: string = '#FF000000';
  @Prop playlistImportSheetHeight: SheetSize = SheetSize.FIT_CONTENT;
  @Prop playlistImportShowClose: boolean = true;
  onOpenArtwork: (detail: TrackDetail, index: number) => void =
    (_detail: TrackDetail, _index: number): void => {};
  onCloseArtwork: () => void = (): void => {};
  onArtworkViewerDisappear: () => void = (): void => {};
  onTrackDetailDisappear: () => void = (): void => {};
  @BuilderParam playlistImportContent: () => void = this.EmptyContent;

  private usesWideLayout(): boolean {
    return this.rootWidth >= AppShellLayoutSpec.SIDE_NAVIGATION_BREAKPOINT;
  }

  private trackDetailSheetWidth(): number {
    if (!this.usesWideLayout()) {
      return Math.max(0, this.rootWidth);
    }
    return Math.min(
      TRACK_DETAIL_SHEET_MAX_WIDTH,
      Math.max(AppShellLayoutSpec.SIDE_NAVIGATION_BREAKPOINT, this.rootWidth - TRACK_DETAIL_SHEET_MIN_MARGIN)
    );
  }

  private trackDetailSheetType(): SheetType {
    return this.usesWideLayout() ? SheetType.SIDE : SheetType.BOTTOM;
  }

  @Builder
  private EmptyContent() {
    Stack()
  }

  @Builder
  private TrackArtworkViewerCover() {
    Stack() {
      if (this.artworkViewerState !== undefined) {
        TrackArtworkViewer({
          state: this.artworkViewerState,
          topInset: this.topInset,
          bottomInset: this.bottomInset,
          onClose: this.onCloseArtwork
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FF000000')
  }

  @Builder
  private TrackDetailSheet() {
    if (this.trackDetailState.state !== undefined) {
      TrackDetailPage({
        store: this.libraryStore,
        state: this.trackDetailState.state,
        topInset: 0,
        bottomInset: 0,
        rootWidth: this.trackDetailSheetWidth(),
        themeBackground: this.themePageBackground,
        reserveFloatingControls: false,
        scroller: this.trackDetailState.scroller,
        onOpenArtwork: this.onOpenArtwork
      })
      .bindContentCover(
        $$this.artworkViewerVisible,
        this.TrackArtworkViewerCover(),
        {
          modalTransition: ModalTransition.ALPHA,
          backgroundColor: '#FF000000',
          enableSafeArea: false,
          onDisappear: this.onArtworkViewerDisappear
        }
      )
    }
  }

  build() {
    Stack() {
      Stack()
        .width(1)
        .height(1)
        .opacity(0)
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.trackDetailVisible, this.TrackDetailSheet(), {
          height: SheetSize.LARGE,
          width: this.trackDetailSheetWidth(),
          preferType: this.trackDetailSheetType(),
          title: { title: '文件信息' },
          dragBar: !this.usesWideLayout(),
          showClose: true,
          backgroundColor: this.themePageBackground,
          onDisappear: this.onTrackDetailDisappear
        })

      Stack()
        .width(1)
        .height(1)
        .opacity(0)
        .hitTestBehavior(HitTestMode.None)
        .bindSheet($$this.playlistImportVisible, this.playlistImportContent(), {
          height: this.playlistImportSheetHeight,
          dragBar: true,
          showClose: this.playlistImportShowClose
        })
    }
    .width(1)
    .height(1)
  }
}
