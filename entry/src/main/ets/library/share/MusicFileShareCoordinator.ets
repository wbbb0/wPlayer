import { common } from '@kit.AbilityKit';
import {
  MusicFileShareDataKind,
  MusicFileShareError,
  MusicFileShareErrorKind,
  MusicFileSharePayload,
  MusicFileSharePresenter,
  MusicFileShareTrack,
  PickerUriAccessActivator,
  TrackShareSource
} from './MusicFileSharePorts';

export class MusicFileShareCoordinator {
  private readonly source: TrackShareSource;
  private readonly uriAccess: PickerUriAccessActivator;
  private readonly presenter: MusicFileSharePresenter;

  constructor(source: TrackShareSource, uriAccess: PickerUriAccessActivator,
    presenter: MusicFileSharePresenter) {
    this.source = source;
    this.uriAccess = uriAccess;
    this.presenter = presenter;
  }

  async share(context: common.UIAbilityContext, trackId: number): Promise<void> {
    let detail: MusicFileShareTrack | undefined;
    try {
      detail = await this.source.getShareTrack(trackId);
    } catch (_) {
      throw new MusicFileShareError(
        MusicFileShareErrorKind.TRACK_LOOKUP_FAILED,
        '无法读取音乐文件信息，请稍后再试'
      );
    }
    if (detail === undefined) {
      throw new MusicFileShareError(
        MusicFileShareErrorKind.TRACK_NOT_FOUND,
        '找不到这首音乐，可能已从音乐库移除'
      );
    }
    if (detail.uri.trim().length === 0) {
      throw new MusicFileShareError(
        MusicFileShareErrorKind.URI_MISSING,
        '这首音乐没有可分享的原始文件'
      );
    }

    let accessActivated: boolean = false;
    try {
      accessActivated = await this.uriAccess.activate(detail.uri);
    } catch (_) {
      accessActivated = false;
    }
    if (!accessActivated) {
      throw new MusicFileShareError(
        MusicFileShareErrorKind.AUTHORIZATION_FAILED,
        '音乐文件授权已失效，请重新导入后再试'
      );
    }

    const payload: MusicFileSharePayload = {
      kind: MusicFileShareDataKind.AUDIO,
      uri: detail.uri,
      title: detail.displayName.trim().length > 0 ? detail.displayName : detail.title,
      description: detail.artistDisplay
    };
    try {
      await this.presenter.show(context, payload);
    } catch (_) {
      throw new MusicFileShareError(
        MusicFileShareErrorKind.SHARE_PANEL_FAILED,
        '无法打开系统分享，请稍后再试'
      );
    }
  }
}
