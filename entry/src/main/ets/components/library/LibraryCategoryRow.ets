import {
  LibraryCategoryKind,
  LibraryCategoryListItem
} from '../../library/model/LibraryModels';
import { LibraryTrackRowStyle } from './LibraryTrackRow';

@Reusable
@Component
export struct LibraryCategoryRow {
  @Prop item: LibraryCategoryListItem;
  @Prop horizontalInset: number = 16;
  @Prop verticalInset: number = 8;
  onActivate: (item: LibraryCategoryListItem) => void = (_item: LibraryCategoryListItem): void => {};

  aboutToReuse(params: ESObject): void {
    this.onActivate = params.onActivate as (item: LibraryCategoryListItem) => void;
  }

  private subtitle(): string {
    if (this.item.kind === LibraryCategoryKind.ARTIST && this.item.albumCount > 0) {
      return `${this.item.trackCount} 首歌曲 · ${this.item.albumCount} 张专辑`;
    }
    return `${this.item.trackCount} 首歌曲`;
  }

  build() {
    Row() {
      Column({ space: LibraryTrackRowStyle.LIBRARY_TEXT_SPACE }) {
        Text(this.item.name)
          .fontSize(LibraryTrackRowStyle.LIBRARY_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.subtitle())
          .fontSize(LibraryTrackRowStyle.LIBRARY_SECONDARY_SIZE)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.horizontalInset,
      right: this.horizontalInset,
      top: this.verticalInset,
      bottom: this.verticalInset
    })
    .hoverEffect(HoverEffect.None)
    .onClick((): void => this.onActivate(this.item))
  }
}
