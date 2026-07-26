import { describe, expect, it } from '@ohos/hypium';
import {
  FloatingWindowAutoCloseBehavior,
  FloatingWindowOpenBehavior,
  FloatingWindowSettingsPolicy
} from '../main/ets/settings/FloatingWindowSettingsPolicy';

export default function floatingWindowSettingsPolicyTest() {
  describe('FloatingWindowSettingsPolicy', () => {
    it('uses the requested defaults', 0, () => {
      expect(FloatingWindowSettingsPolicy.OPEN_BEHAVIOR_DEFAULT)
        .assertEqual(FloatingWindowOpenBehavior.MINIMIZE_APP);
      expect(FloatingWindowSettingsPolicy.AUTO_START_ON_MINIMIZE_DEFAULT).assertFalse();
      expect(FloatingWindowSettingsPolicy.AUTO_CLOSE_BEHAVIOR_DEFAULT)
        .assertEqual(FloatingWindowAutoCloseBehavior.APP_FOREGROUND);
    });

    it('normalizes stored behavior values and preserves the legacy minimize choice', 0, () => {
      expect(FloatingWindowSettingsPolicy.normalizeOpenBehavior(-1))
        .assertEqual(FloatingWindowOpenBehavior.MINIMIZE_APP);
      expect(FloatingWindowSettingsPolicy.normalizeAutoCloseBehavior(99))
        .assertEqual(FloatingWindowAutoCloseBehavior.APP_FOREGROUND);
      expect(FloatingWindowSettingsPolicy.openBehaviorFromLegacy(true))
        .assertEqual(FloatingWindowOpenBehavior.MINIMIZE_APP);
      expect(FloatingWindowSettingsPolicy.openBehaviorFromLegacy(false))
        .assertEqual(FloatingWindowOpenBehavior.DO_NOTHING);
    });

    it('maps explicit PiP completion behavior to one owning action', 0, () => {
      expect(FloatingWindowSettingsPolicy.shouldMinimizeAfterOpen(
        FloatingWindowOpenBehavior.MINIMIZE_APP
      )).assertTrue();
      expect(FloatingWindowSettingsPolicy.shouldMinimizeAfterOpen(
        FloatingWindowOpenBehavior.CLOSE_PLAYER_PAGE
      )).assertFalse();
      expect(FloatingWindowSettingsPolicy.shouldClosePlayerPageAfterOpen(
        FloatingWindowOpenBehavior.CLOSE_PLAYER_PAGE
      )).assertTrue();
      expect(FloatingWindowSettingsPolicy.shouldClosePlayerPageAfterOpen(
        FloatingWindowOpenBehavior.DO_NOTHING
      )).assertFalse();
    });

    it('closes PiP only for the selected automatic close trigger', 0, () => {
      expect(FloatingWindowSettingsPolicy.shouldCloseOnForeground(
        FloatingWindowAutoCloseBehavior.APP_FOREGROUND
      )).assertTrue();
      expect(FloatingWindowSettingsPolicy.shouldCloseOnForeground(
        FloatingWindowAutoCloseBehavior.PLAYER_PAGE_OPENED
      )).assertFalse();
      expect(FloatingWindowSettingsPolicy.shouldCloseOnPlayerPageOpened(
        FloatingWindowAutoCloseBehavior.PLAYER_PAGE_OPENED
      )).assertTrue();
      expect(FloatingWindowSettingsPolicy.shouldCloseOnPlayerPageOpened(
        FloatingWindowAutoCloseBehavior.NEVER
      )).assertFalse();
    });

    it('enables automatic PiP only for active playback', 0, () => {
      expect(FloatingWindowSettingsPolicy.shouldEnableAutoStart(true, true, true)).assertTrue();
      expect(FloatingWindowSettingsPolicy.shouldEnableAutoStart(false, true, true)).assertFalse();
      expect(FloatingWindowSettingsPolicy.shouldEnableAutoStart(true, false, true)).assertFalse();
      expect(FloatingWindowSettingsPolicy.shouldEnableAutoStart(true, true, false)).assertFalse();
    });
  });
}
