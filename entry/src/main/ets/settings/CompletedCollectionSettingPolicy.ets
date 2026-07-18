import { CompletedCollectionMode } from '../playback/model/PlaybackModels';

const MODE_LABELS: Array<string> = ['智能', '默认开启', '默认关闭'];

export class CompletedCollectionSettingPolicy {
  static normalize(value: number): CompletedCollectionMode {
    if (value >= CompletedCollectionMode.SMART && value <= CompletedCollectionMode.DEFAULT_OFF) {
      return value as CompletedCollectionMode;
    }
    return CompletedCollectionMode.SMART;
  }

  static label(value: number): string {
    return MODE_LABELS[CompletedCollectionSettingPolicy.normalize(value)];
  }
}
