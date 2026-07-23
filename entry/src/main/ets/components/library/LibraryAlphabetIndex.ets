import { LibrarySection } from '../../library/model/LibraryModels';
import { LayoutLength } from '../layout/LayoutLength';

@Component
export struct LibraryAlphabetIndex {
  private static readonly ITEM_SIZE: number = 16;
  private static readonly POPUP_X: number = 32;
  @Prop sections: Array<LibrarySection> = [];
  @Prop selectedIndex: number = 0;
  @State indexerHeight: number = 0;
  onSelect: (itemIndex: number, sectionIndex: number) => void = () => {};

  private labels(): Array<string> {
    return this.sections.map((section: LibrarySection) => section.label);
  }

  private effectiveSelectedIndex(): number {
    return Math.max(0, Math.min(this.selectedIndex, Math.max(0, this.sections.length - 1)));
  }

  private popupY(): number {
    if (this.indexerHeight <= 0 || this.sections.length <= 1) {
      return 0;
    }
    const availableTravel = Math.max(0, this.indexerHeight - LibraryAlphabetIndex.ITEM_SIZE);
    return this.effectiveSelectedIndex() * availableTravel / (this.sections.length);
  }

  build() {
    AlphabetIndexer({ arrayValue: this.labels(), selected: 0 })
      .selected(this.effectiveSelectedIndex())
      .width(28)
      .height('90%')
      .itemSize(LibraryAlphabetIndex.ITEM_SIZE)
      .usingPopup(true)
      .popupPosition({ x: LibraryAlphabetIndex.POPUP_X, y: this.popupY() })
      .alignStyle(IndexerAlign.END)
      .autoCollapse(true)
      .enableHapticFeedback(true)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.indexerHeight = LayoutLength.toNumber(newValue.height, this.indexerHeight);
      })
      .onSelect((index: number) => {
        if (index >= 0 && index < this.sections.length) {
          this.onSelect(this.sections[index].startIndex, index);
        }
      })
  }
}
