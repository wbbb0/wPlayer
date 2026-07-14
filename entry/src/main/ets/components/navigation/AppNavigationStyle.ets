import {
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarOptions,
  ScrollEffectType,
  TitleBarContentOptions,
  hdsMaterial
} from '@kit.UIDesignKit';
import { ComponentContent } from '@kit.ArkUI';
import { AppPrimaryTitleParams } from './AppPrimaryTitleContent';

export class AppNavigationStyle {
  static primaryTitleBar(title: string, menu?: HdsNavigationMenuContentOptions,
    titleContent?: ComponentContent<AppPrimaryTitleParams>): HdsNavigationTitleBarOptions {
    return AppNavigationStyle.createTitleBar(title, true, true, menu, titleContent);
  }

  static secondaryTitleBar(title: string): HdsNavigationTitleBarOptions {
    return AppNavigationStyle.createTitleBar(title, true, true);
  }

  private static createTitleBar(title: string, avoidLayoutSafeArea: boolean, enableComponentSafeArea: boolean,
    menu?: HdsNavigationMenuContentOptions,
    titleContent?: ComponentContent<AppPrimaryTitleParams>): HdsNavigationTitleBarOptions {
    const content: TitleBarContentOptions = { menu: menu };
    if (titleContent === undefined) {
      content.title = { mainTitle: title };
    } else {
      content.stackBuilderComponent = titleContent;
    }
    return {
      avoidLayoutSafeArea: avoidLayoutSafeArea,
      enableComponentSafeArea: enableComponentSafeArea,
      content: content,
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    };
  }
}
