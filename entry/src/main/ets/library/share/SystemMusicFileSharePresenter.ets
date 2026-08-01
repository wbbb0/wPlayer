import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import {
  MusicFileShareDataKind,
  MusicFileSharePayload,
  MusicFileSharePresenter
} from './MusicFileSharePorts';
import { common } from '@kit.AbilityKit';

export class SystemMusicFileSharePresenter implements MusicFileSharePresenter {
  async show(context: common.UIAbilityContext, payload: MusicFileSharePayload): Promise<void> {
    try {
      const data = new systemShare.SharedData({
        utd: this.utdOf(payload.kind),
        uri: payload.uri,
        title: payload.title,
        description: payload.description
      });
      const controller = new systemShare.ShareController(data);
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (error) {
      throw error as Error;
    }
  }

  private utdOf(kind: MusicFileShareDataKind): string {
    switch (kind) {
      case MusicFileShareDataKind.AUDIO:
      default:
        return uniformTypeDescriptor.UniformDataType.AUDIO;
    }
  }
}
