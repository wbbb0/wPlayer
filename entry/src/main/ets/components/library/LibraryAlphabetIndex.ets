import { LibrarySection } from '../../library/model/LibraryModels';

@Component
export struct LibraryAlphabetIndex {
  @Prop sections: Array<LibrarySection> = [];
  @State selectedIndex: number = 0;
  onSelect: (itemIndex: number) => void = () => {};

  private labels(): Array<string> {
    return this.sections.map((section: LibrarySection) => section.label);
  }

  build() {
    AlphabetIndexer({ arrayValue: this.labels(), selected: this.selectedIndex })
      .width(28)
      .height('80%')
      .usingPopup(true)
      .alignStyle(IndexerAlign.END)
      .autoCollapse(true)
      .enableHapticFeedback(true)
      .onSelect((index: number) => {
        if (index >= 0 && index < this.sections.length) {
          this.selectedIndex = index;
          this.onSelect(this.sections[index].startIndex);
        }
      })
  }
}
