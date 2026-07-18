import { LibrarySection } from '../../library/model/LibraryModels';

@Component
export struct LibraryAlphabetIndex {
  @Prop sections: Array<LibrarySection> = [];
  @Prop selectedIndex: number = 0;
  onSelect: (itemIndex: number, sectionIndex: number) => void = () => {};

  private labels(): Array<string> {
    return this.sections.map((section: LibrarySection) => section.label);
  }

  private effectiveSelectedIndex(): number {
    return Math.max(0, Math.min(this.selectedIndex, Math.max(0, this.sections.length - 1)));
  }

  build() {
    AlphabetIndexer({ arrayValue: this.labels(), selected: 0 })
      .selected(this.effectiveSelectedIndex())
      .width(28)
      .height('80%')
      .usingPopup(true)
      .alignStyle(IndexerAlign.END)
      .autoCollapse(true)
      .enableHapticFeedback(true)
      .onSelect((index: number) => {
        if (index >= 0 && index < this.sections.length) {
          this.onSelect(this.sections[index].startIndex, index);
        }
      })
  }
}
