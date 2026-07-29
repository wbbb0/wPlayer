export class TabReselectionPolicy {
  static isReselection(clickedIndex: number, selectedIndex: number): boolean {
    return clickedIndex === selectedIndex;
  }
}
