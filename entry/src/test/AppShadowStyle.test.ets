import { describe, expect, it } from '@ohos/hypium';
import { AppShadowStyle } from '../main/ets/appearance/AppShadowStyle';

export default function appShadowStyleTest() {
  describe('Shadow visibility across API versions', () => {
    it('removesZeroRadiusShadowsEvenWhenTheSurfaceRetainsAnOffset', 0, () => {
      expect(AppShadowStyle.radius(0)).assertEqual(-1);
    });
    it('removesDisabledArtworkShadowsWithoutChangingTheirConfiguredRadius', 0, () => {
      expect(AppShadowStyle.radius(14, false)).assertEqual(-1);
    });
    it('preservesEnabledBlurredShadows', 0, () => {
      expect(AppShadowStyle.radius(14)).assertEqual(14);
      expect(AppShadowStyle.radius(0.5)).assertEqual(0.5);
    });
    it('keepsNegativeAndInvalidRadiiInvisible', 0, () => {
      expect(AppShadowStyle.radius(-1)).assertEqual(-1);
      expect(AppShadowStyle.radius(Number.NaN)).assertEqual(-1);
    });
  });
}
