import {
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleBarOptions,
  HdsTitleBarContentStyle,
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
        originalStyle: AppNavigationStyle.foregroundStyle(),
        scrollEffectStyle: AppNavigationStyle.foregroundStyle(),
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    };
  }

  private static foregroundStyle(): HdsNavigationTitleBarStyle {
    const contentStyle: HdsTitleBarContentStyle = {
      titleStyle: {
        mainTitleColor: $r('app.color.text_primary'),
        subTitleColor: $r('app.color.text_secondary')
      },
      menuStyle: {
        iconColor: $r('app.color.text_primary'),
        textColor: $r('app.color.text_primary')
      },
      backIconStyle: {
        iconColor: $r('app.color.text_primary'),
        textColor: $r('app.color.text_primary')
      },
      subIconStyle: {
        iconColor: $r('app.color.text_primary'),
        textColor: $r('app.color.text_primary')
      }
    };
    return { contentStyle: contentStyle };
  }
}
