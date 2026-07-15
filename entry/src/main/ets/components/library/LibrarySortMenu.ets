import { SymbolGlyphModifier } from '@kit.ArkUI';

export class LibrarySortMenuParams {
  readonly labels: Array<string>;
  readonly selectedIndex: number;
  readonly descending: boolean;
  readonly onFieldChange: (index: number) => void;
  readonly onDirectionChange: (descending: boolean) => void;

  constructor(labels: Array<string>, selectedIndex: number, descending: boolean,
    onFieldChange: (index: number) => void, onDirectionChange: (descending: boolean) => void) {
    this.labels = labels;
    this.selectedIndex = selectedIndex;
    this.descending = descending;
    this.onFieldChange = onFieldChange;
    this.onDirectionChange = onDirectionChange;
  }
}

@Builder
export function LibrarySortMenu(params: LibrarySortMenuParams) {
  Menu() {
    ForEach(params.labels, (label: string, index: number) => {
      MenuItem({
        content: label,
        symbolEndIcon: index === params.selectedIndex ?
          new SymbolGlyphModifier($r('sys.symbol.checkmark')) : undefined
      })
        .onClick(() => {
          params.onFieldChange(index);
        })
    }, (label: string) => label)

    MenuItem({
      content: params.descending ? '倒序' : '正序',
      labelInfo: '切换'
    })
      .onClick(() => {
        params.onDirectionChange(!params.descending);
      })
  }
  .width(224)
}
