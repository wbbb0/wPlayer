import { PlaylistSummary } from '../../library/model/LibraryModels';
import { LayoutLength } from '../layout/LayoutLength';
import { LibraryContextInteraction } from './LibraryContextInteraction';
import { LibraryTrackRowStyle } from './LibraryTrackRow';

@Reusable
@Component
export struct PlaylistListRow {
  @Prop playlist: PlaylistSummary;
  @Prop subtitle: string = '';
  @Prop leadingSymbol: Resource;
  @Prop actionAnchorPrefix: string = 'playlists';
  @Prop horizontalInset: number = 16;
  @Prop verticalInset: number = 8;
  @Prop leadingSize: number = 52;
  @Prop leadingCornerRadius: number = 10;
  @Prop selectionMode: boolean = false;
  @Prop selected: boolean = false;
  onActivate: (playlist: PlaylistSummary) => void =
    (_playlist: PlaylistSummary): void => {};
  onToggleSelection: (playlist: PlaylistSummary) => void =
    (_playlist: PlaylistSummary): void => {};
  @Builder
  private EmptyMenu() {
  }
  @BuilderParam contextMenu: () => void = this.EmptyMenu;
  @State contextMenuShown: boolean = false;
  private measuredIdentityWidth: number = 0;
  private suppressActivationUntil: number = 0;

  aboutToReuse(params: ESObject): void {
    this.contextMenuShown = false;
    this.measuredIdentityWidth = 0;
    this.suppressActivationUntil = 0;
    this.onActivate = params.onActivate as (playlist: PlaylistSummary) => void;
    this.onToggleSelection =
      params.onToggleSelection as (playlist: PlaylistSummary) => void;
    if (params.contextMenu !== undefined) {
      this.contextMenu = params.contextMenu as () => void;
    }
  }

  private actionAnchorId(): string {
    return `playlist_more_${this.actionAnchorPrefix}_${this.playlist.id}`;
  }

  private contextPreviewAnchorId(): string {
    return `playlist_context_preview_${this.actionAnchorPrefix}_${this.playlist.id}`;
  }

  private effectiveContextPreviewWidth(): number {
    return this.measuredIdentityWidth > 0 ? this.measuredIdentityWidth :
      LibraryTrackRowStyle.CONTEXT_PREVIEW_FALLBACK_WIDTH;
  }

  private showContextMenu(): void {
    try {
      const uiContext = this.getUIContext();
      const info = uiContext.getComponentUtils().getRectangleById(this.contextPreviewAnchorId());
      const width = uiContext.px2vp(LayoutLength.toNumber(info.size.width, 0));
      if (width > 0) {
        this.measuredIdentityWidth = width;
      }
    } catch (error) {
      console.warn(`Unable to measure playlist context preview: ${error}`);
    }
    this.suppressActivationUntil =
      Date.now() + LibraryContextInteraction.ACTIVATION_SUPPRESSION_DURATION;
    LibraryContextInteraction.triggerHaptic('Playlist');
    this.contextMenuShown = true;
  }

  @Builder
  private LeadingContent() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(this.leadingSymbol)
        .fontSize(28)
        .fontColor([$r('app.color.theme_accent')])
    }
    .width(this.leadingSize)
    .height(this.leadingSize)
    .borderRadius(this.leadingCornerRadius)
    .backgroundColor($r('app.color.glass_surface_strong'))
  }

  @Builder
  private TextContent() {
    Column({ space: LibraryTrackRowStyle.LIBRARY_TEXT_SPACE }) {
      Text(this.playlist.name)
        .fontSize(LibraryTrackRowStyle.LIBRARY_TITLE_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.subtitle)
        .fontSize(LibraryTrackRowStyle.LIBRARY_SECONDARY_SIZE)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .clip(true)
  }

  @Builder
  private IdentityContent() {
    Row({ space: LibraryTrackRowStyle.CONTENT_SPACE }) {
      this.LeadingContent()
      this.TextContent()
    }
    .width('100%')
    .clip(true)
  }

  @Builder
  private ContextMenuPreview() {
    Row({ space: LibraryTrackRowStyle.CONTENT_SPACE }) {
      this.LeadingContent()
      this.TextContent()
    }
    .width(this.effectiveContextPreviewWidth())
  }

  @Builder
  private SelectionIndicator() {
    Stack() {
      SymbolGlyph(this.selected ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
        .fontSize(22)
        .fontColor([
          this.selected ? $r('app.color.theme_accent') : $r('app.color.text_tertiary')
        ])
    }
    .width(this.selectionMode ? LibraryTrackRowStyle.SELECTION_WIDTH : 0)
    .opacity(this.selectionMode ? 1 : 0)
    .translate({ x: this.selectionMode ? 0 : -12 })
    .margin({ right: this.selectionMode ? LibraryTrackRowStyle.SELECTION_GAP : 0 })
    .clip(true)
    .animation({ duration: 180, curve: Curve.EaseOut })
  }

  @Builder
  private InteractiveIdentity() {
    Row() {
      this.IdentityContent()
    }
    .layoutWeight(1)
    .clip(true)
    .id(this.contextPreviewAnchorId())
    .opacity(this.contextMenuShown ? 0 : 1)
    .bindContextMenu(
      this.contextMenuShown,
      this.contextMenu(),
      {
        preview: this.ContextMenuPreview,
        previewBorderRadius: 0,
        onDisappear: (): void => {
          this.contextMenuShown = false;
        }
      }
    )
    .gesture(
      LongPressGesture({
        repeat: false,
        duration: LibraryContextInteraction.LONG_PRESS_DURATION
      }).onAction(() => this.showContextMenu())
    )
  }

  @Builder
  private ActionButton() {
    Button() {
      Image($r('app.media.control_more'))
        .width(LibraryTrackRowStyle.ACTION_ICON_SIZE)
        .height(LibraryTrackRowStyle.ACTION_ICON_SIZE)
        .fillColor($r('app.color.text_primary'))
    }
    .width(LibraryTrackRowStyle.ACTION_SIZE)
    .height(LibraryTrackRowStyle.ACTION_SIZE)
    .borderRadius(LibraryTrackRowStyle.ACTION_SIZE / 2)
    .backgroundColor(Color.Transparent)
    .accessibilityText('更多播放列表操作')
    .id(this.actionAnchorId())
    .bindMenu(this.contextMenu, { placement: Placement.BottomRight })
  }

  build() {
    Row({ space: LibraryTrackRowStyle.CONTENT_SPACE }) {
      this.SelectionIndicator()
      if (this.selectionMode) {
        Row() {
          this.IdentityContent()
        }
        .layoutWeight(1)
        .clip(true)
      } else {
        this.InteractiveIdentity()
        this.ActionButton()
      }
    }
    .width('100%')
    .padding({
      left: this.horizontalInset,
      right: this.horizontalInset,
      top: this.verticalInset,
      bottom: this.verticalInset
    })
    .hoverEffect(HoverEffect.None)
    .onClick(() => {
      if (Date.now() < this.suppressActivationUntil) {
        return;
      }
      if (this.selectionMode) {
        this.onToggleSelection(this.playlist);
      } else {
        this.onActivate(this.playlist);
      }
    })
  }
}
