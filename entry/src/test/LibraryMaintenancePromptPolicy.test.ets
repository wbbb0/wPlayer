import { describe, expect, it } from '@ohos/hypium';
import { LibraryMaintenanceKind } from '../main/ets/library/data/MusicRepositoryTypes';
import {
  LibraryMaintenanceAction,
  LibraryMaintenancePromptPolicy
} from '../main/ets/library/maintenance/LibraryMaintenancePromptPolicy';

export default function libraryMaintenancePromptPolicyTest() {
  describe('Library maintenance prompt policy', () => {
    it('composes available maintenance kinds without page-specific copy', 0, () => {
      const prompt = LibraryMaintenancePromptPolicy.fromStatus({
        items: [
          { kind: LibraryMaintenanceKind.ARTWORK_COLORS, count: 3 },
          { kind: LibraryMaintenanceKind.ARTWORK_VARIANTS, count: 5 }
        ],
        total: 8
      });
      expect(prompt.message.includes('WebP 封面缓存')).assertTrue();
      expect(prompt.message.includes('封面色彩')).assertTrue();
      expect(prompt.detail.includes('WebP 封面缓存 5 项')).assertTrue();
      expect(prompt.detail.includes('封面色彩 3 项')).assertTrue();
      expect(prompt.primaryAction).assertEqual(LibraryMaintenanceAction.CHECK_MUSIC_FILES);
    });

    it('keeps an empty status renderable for component defaults', 0, () => {
      const prompt = LibraryMaintenancePromptPolicy.fromStatus({ items: [], total: 0 });
      expect(prompt.detail).assertEqual('');
      expect(prompt.primaryActionLabel.length).assertLarger(0);
      expect(prompt.secondaryActionLabel.length).assertLarger(0);
    });
  });
}
