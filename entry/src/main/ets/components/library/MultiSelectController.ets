import {
  MenuSectionDivider
} from './MenuActionGroups';

export class MultiSelectActionMenuParams {
  readonly controller: MultiSelectController;

  constructor(controller: MultiSelectController) {
    this.controller = controller;
  }
}

@Observed
export class MultiSelectController {
  active: boolean = false;
  selectedIds: Array<number> = [];
  pendingIds: Array<number> = [];
  pendingSelected: boolean = true;
  deleteEnabled: boolean = false;
  busy: boolean = false;
  onPlay: () => void = (): void => {};
  onAddToPlaylist: () => void = (): void => {};
  onInsertNext: () => void = (): void => {};
  onAppendToQueue: () => void = (): void => {};
  onDelete: () => void = (): void => {};
  onToggleAll: () => void = (): void => {};
  onStateChange: () => void = (): void => {};
  selectableCount: number = 0;

  activate(): void {
    this.active = true;
    this.selectedIds = [];
    this.pendingIds = [];
    this.onStateChange();
  }

  cancel(): void {
    this.active = false;
    this.selectedIds = [];
    this.pendingIds = [];
    this.busy = false;
    this.onStateChange();
  }

  isSelected(id: number): boolean {
    return this.selectedIds.includes(id);
  }

  toggle(id: number): void {
    if (!this.active) {
      return;
    }
    if (this.isSelected(id)) {
      this.selectedIds = this.selectedIds.filter((selectedId: number): boolean => selectedId !== id);
    } else {
      this.selectedIds = this.selectedIds.concat([id]);
    }
    this.onStateChange();
  }

  isPresentedSelected(id: number): boolean {
    return this.pendingIds.includes(id) ? this.pendingSelected : this.isSelected(id);
  }

  previewSelection(ids: Array<number>, selected: boolean): void {
    if (!this.active) {
      this.pendingIds = [];
      return;
    }
    this.pendingIds = ids.slice();
    this.pendingSelected = selected;
  }

  setSelected(id: number, selected: boolean): void {
    if (!this.active || this.isSelected(id) === selected) {
      return;
    }
    if (selected) {
      this.selectedIds = this.selectedIds.concat([id]);
    } else {
      this.selectedIds = this.selectedIds.filter((selectedId: number): boolean => selectedId !== id);
    }
    this.onStateChange();
  }

  replaceSelection(ids: Array<number>): void {
    if (!this.active) {
      return;
    }
    this.selectedIds = ids.slice();
    this.pendingIds = [];
    this.onStateChange();
  }

  allSelected(): boolean {
    return this.selectableCount > 0 && this.selectedIds.length === this.selectableCount;
  }

  toggleAll(): void {
    if (!this.active || this.busy || this.selectableCount === 0) {
      return;
    }
    this.onToggleAll();
  }

  setBusy(busy: boolean): void {
    this.busy = busy;
    this.onStateChange();
  }

  selectedCount(): number {
    return this.selectedIds.length;
  }

  canRunAction(): boolean {
    return this.selectedIds.length > 0 && !this.busy;
  }
}

@Builder
export function MultiSelectActionMenu(params: MultiSelectActionMenuParams) {
  Menu() {
    MenuItem({ content: '播放' })
      .enabled(params.controller.canRunAction())
      .onClick(params.controller.onPlay)
    MenuItem({ content: '插播', labelInfo: '下一首开始' })
      .enabled(params.controller.canRunAction())
      .onClick(params.controller.onInsertNext)
    MenuItem({ content: '追加到播放队列' })
      .enabled(params.controller.canRunAction())
      .onClick(params.controller.onAppendToQueue)
    MenuSectionDivider()
    MenuItem({ content: '添加到播放列表' })
      .enabled(params.controller.canRunAction())
      .onClick(params.controller.onAddToPlaylist)
    if (params.controller.deleteEnabled) {
      MenuSectionDivider()
      MenuItem({ content: '移除所选项目' })
        .enabled(params.controller.canRunAction())
        .onClick(params.controller.onDelete)
    }
  }
  .width(240)
}
