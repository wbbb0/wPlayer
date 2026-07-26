import { DynamicColor } from '../../appearance/DynamicColor';
import { AppShellLayoutSpec } from './AppShellLayoutSpec';

@Component
export struct PageBottomGradient {
  private static readonly EDGE_OPACITY: number = 0.5;

  @Prop maskColor: string = '#FF000000';

  build() {
    Blank()
      .width('100%')
      .height(AppShellLayoutSpec.FLOATING_BAR_GRADIENT_MASK_HEIGHT)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [
          [DynamicColor.withOpacity(this.maskColor, 0), 0],
          [DynamicColor.withOpacity(this.maskColor, PageBottomGradient.EDGE_OPACITY), 1]
        ]
      })
      .hitTestBehavior(HitTestMode.None)
  }
}
