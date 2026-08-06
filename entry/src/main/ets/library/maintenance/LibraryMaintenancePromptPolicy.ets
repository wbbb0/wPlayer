import {
  LibraryMaintenanceKind,
  LibraryMaintenanceStatus
} from '../data/MusicRepositoryTypes';

export enum LibraryMaintenanceAction {
  CHECK_MUSIC_FILES = 0
}

export interface LibraryMaintenancePromptDescriptor {
  kind: LibraryMaintenanceKind;
  label: string;
}

export interface LibraryMaintenancePrompt {
  title: string;
  message: string;
  detail: string;
  footer: string;
  primaryActionLabel: string;
  secondaryActionLabel: string;
  primaryAction: LibraryMaintenanceAction;
}

export class LibraryMaintenancePromptPolicy {
  private static readonly DESCRIPTORS: Array<LibraryMaintenancePromptDescriptor> = [
    { kind: LibraryMaintenanceKind.ARTWORK_VARIANTS, label: 'WebP 封面缓存' },
    { kind: LibraryMaintenanceKind.ARTWORK_COLORS, label: '封面色彩' }
  ];

  static fromStatus(status: LibraryMaintenanceStatus): LibraryMaintenancePrompt {
    const details: Array<string> = [];
    const labels: Array<string> = [];
    LibraryMaintenancePromptPolicy.DESCRIPTORS.forEach(
      (descriptor: LibraryMaintenancePromptDescriptor): void => {
        const item = status.items.find((candidate): boolean => candidate.kind === descriptor.kind);
        if (item !== undefined && item.count > 0) {
          labels.push(descriptor.label);
          details.push(`${descriptor.label} ${item.count} 项`);
        }
      }
    );
    const subjects = labels.length > 0 ? labels.join('、') : '音乐库信息';
    return {
      title: '音乐库需要一次整理',
      message: `新版优化了${subjects}。运行一次“检查音乐文件”，即可更新已有内容。`,
      detail: details.length > 0 ? `发现${details.join('，')}可以更新` : '',
      footer: '暂不处理不会影响播放，现有内容会继续使用；原始音频文件不会被修改。',
      primaryActionLabel: '前往检查',
      secondaryActionLabel: '稍后再说',
      primaryAction: LibraryMaintenanceAction.CHECK_MUSIC_FILES
    };
  }
}
