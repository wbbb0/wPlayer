export class PlaylistCreateMenuParams {
  readonly onCreate: () => void;
  readonly onImport: () => void;

  constructor(onCreate: () => void, onImport: () => void) {
    this.onCreate = onCreate;
    this.onImport = onImport;
  }
}

@Builder
export function PlaylistCreateMenu(params: PlaylistCreateMenuParams) {
  Menu() {
    MenuItem({ content: '新建播放列表' })
      .onClick(params.onCreate)
    MenuItem({ content: '导入 M3U' })
      .onClick(params.onImport)
  }
  .width(224)
}

export class PlaylistTransferMenuParams {
  readonly onExport: () => void;
  readonly onMerge: () => void;
  readonly onReplace: () => void;
  readonly onRename?: () => void;
  readonly onDelete?: () => void;

  constructor(
    onExport: () => void,
    onMerge: () => void,
    onReplace: () => void,
    onRename?: () => void,
    onDelete?: () => void
  ) {
    this.onExport = onExport;
    this.onMerge = onMerge;
    this.onReplace = onReplace;
    this.onRename = onRename;
    this.onDelete = onDelete;
  }
}

@Builder
export function PlaylistTransferMenu(params: PlaylistTransferMenuParams) {
  Menu() {
    MenuItem({ content: '导出为 M3U8' })
      .onClick(params.onExport)
    MenuItem({ content: '导入并合并' })
      .onClick(params.onMerge)
    MenuItem({ content: '导入并替换全部内容' })
      .onClick(params.onReplace)
    if (params.onRename !== undefined) {
      MenuItem({ content: '播放列表改名' })
        .onClick(() => params.onRename?.())
    }
    if (params.onDelete !== undefined) {
      MenuItem({ content: '删除播放列表' })
        .onClick(() => params.onDelete?.())
    }
  }
  .width(240)
}
