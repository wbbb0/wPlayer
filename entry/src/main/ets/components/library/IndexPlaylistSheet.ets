import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { PlaylistSelectionSheet } from './PlaylistSelectionSheet';

export enum IndexPlaylistSheetKind {
  CREATE = 0,
  PICKER = 1,
  RENAME = 2
}

@Component
export struct IndexPlaylistSheet {
  @ObjectLink store: PlaylistStore;
  @Prop kind: IndexPlaylistSheetKind = IndexPlaylistSheetKind.CREATE;
  @Prop createName: string = '';
  @Prop renameName: string = '';
  @Prop pickerTrackIds: Array<number> = [];
  @Prop recentPlaylistTargetIds: Array<number> = [];
  onCreateNameChange: (value: string) => void = (_value: string): void => {};
  onRenameNameChange: (value: string) => void = (_value: string): void => {};
  onSaveCreate: () => void = (): void => {};
  onSaveRename: () => void = (): void => {};
  onAddedToPlaylist: (playlistId: number, message: string) => void =
    (_playlistId: number, _message: string): void => {};
  onClose: () => void = (): void => {};

  @Builder
  private PlaylistCreator() {
    Column({ space: 18 }) {
      Text('新建播放列表')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({
        text: this.createName,
        placeholder: '播放列表名称'
      })
        .width('100%')
        .onChange((value: string) => {
          this.onCreateNameChange(value);
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => {
            this.onClose();
          })
        Button('创建')
          .layoutWeight(1)
          .enabled(this.createName.trim().length > 0 && !this.store.mutating)
          .onClick(() => this.onSaveCreate())
      }
      .width('100%')
    }
    .padding(24)
    .width('100%')
  }

  @Builder
  private PlaylistPicker() {
    PlaylistSelectionSheet({
      store: this.store,
      trackIds: this.pickerTrackIds,
      recentPlaylistIds: this.recentPlaylistTargetIds,
      onAddedToPlaylist: (playlistId: number, message: string): void =>
        this.onAddedToPlaylist(playlistId, message),
      onClose: (): void => {
        this.onClose();
      }
    })
  }

  @Builder
  private PlaylistRenamer() {
    Column({ space: 18 }) {
      Text('播放列表改名')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({
        text: this.renameName,
        placeholder: '播放列表名称'
      })
        .width('100%')
        .onChange((value: string) => {
          this.onRenameNameChange(value);
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .onClick(() => {
            this.onClose();
          })
        Button('保存')
          .layoutWeight(1)
          .enabled(this.renameName.trim().length > 0 && !this.store.mutating)
          .onClick(() => this.onSaveRename())
      }
      .width('100%')
    }
    .padding(24)
    .width('100%')
  }

  build() {
    if (this.kind === IndexPlaylistSheetKind.PICKER) {
      this.PlaylistPicker()
    } else if (this.kind === IndexPlaylistSheetKind.RENAME) {
      this.PlaylistRenamer()
    } else {
      this.PlaylistCreator()
    }
  }
}
