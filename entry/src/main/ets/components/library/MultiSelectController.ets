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
  deleteEnabled: boolean = false;
  busy: boolean = false;
  onPlay: () => void = (): void => {};
  onAddToPlaylist: () => void = (): void => {};
  onInsertNext: () => void = (): void => {};
  onAppendToQueue: () => void = (): void => {};
  onDelete: () => void = (): void => {};
  onStateChange: () => void = (): void => {};

  activate(): void {
    this.active = true;
    this.selectedIds = [];
    this.onStateChange();
  }

  cancel(): void {
    this.active = false;
    this.selectedIds = [];
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
    MenuItem({ content: '添加到播放列表' })
      .enabled(params.controller.canRunAction())
      .onClick(params.controller.onAddToPlaylist)
    MenuItem({ content: '插播', labelInfo: '下一首开始' })
      .enabled(params.controller.canRunAction())
      .onClick(params.controller.onInsertNext)
    MenuItem({ content: '追加到播放队列' })
      .enabled(params.controller.canRunAction())
      .onClick(params.controller.onAppendToQueue)
    if (params.controller.deleteEnabled) {
      MenuItem({ content: '移除所选项目' })
        .enabled(params.controller.canRunAction())
        .onClick(params.controller.onDelete)
    }
  }
  .width(240)
}
