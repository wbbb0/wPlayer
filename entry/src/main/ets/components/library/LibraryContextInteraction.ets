import { BusinessError } from '@kit.BasicServicesKit';
import { vibrator } from '@kit.SensorServiceKit';

export class LibraryContextInteraction {
  static readonly LONG_PRESS_DURATION: number = 500;
  static readonly ACTIVATION_SUPPRESSION_DURATION: number = 800;
  private static readonly HAPTIC_EFFECT_ID: string = 'haptic.effect.soft';
  private static readonly HAPTIC_INTENSITY: number = 35;
  private static hapticSupported: boolean | undefined = undefined;

  static triggerHaptic(label: string): void {
    try {
      if (LibraryContextInteraction.hapticSupported === undefined) {
        LibraryContextInteraction.hapticSupported =
          vibrator.isSupportEffectSync(LibraryContextInteraction.HAPTIC_EFFECT_ID);
      }
      if (!LibraryContextInteraction.hapticSupported) {
        return;
      }
      vibrator.startVibration({
        type: 'preset',
        effectId: LibraryContextInteraction.HAPTIC_EFFECT_ID,
        count: 1,
        intensity: LibraryContextInteraction.HAPTIC_INTENSITY
      }, {
        id: 0,
        usage: 'touch'
      }).catch((error: BusinessError) => {
        console.warn(`${label} context haptic failed: ${error.code}, ${error.message}`);
      });
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`${label} context haptic unavailable: ${businessError.code}, ${businessError.message}`);
    }
  }
}
