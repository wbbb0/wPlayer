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
import { AppAppearancePalette } from '../../appearance/AppAppearance';
import { AppPrimaryTitleParams } from './AppPrimaryTitleContent';

export class AppNavigationStyle {
  static primaryTitleBar(title: string, palette: AppAppearancePalette, menu?: HdsNavigationMenuContentOptions,
    titleContent?: ComponentContent<AppPrimaryTitleParams>): HdsNavigationTitleBarOptions {
    return AppNavigationStyle.createTitleBar(title, palette, true, true, menu, titleContent);
  }

  static secondaryTitleBar(title: string, palette: AppAppearancePalette,
    menu?: HdsNavigationMenuContentOptions): HdsNavigationTitleBarOptions {
    return AppNavigationStyle.createTitleBar(title, palette, true, true, menu);
  }

  static secondaryBackOnlyTitleBar(palette: AppAppearancePalette,
    menu?: HdsNavigationMenuContentOptions): HdsNavigationTitleBarOptions {
    return {
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: { menu: menu },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.IMMERSIVE_GRADIENT_BLUR
        },
        originalStyle: AppNavigationStyle.foregroundStyle(palette),
        scrollEffectStyle: AppNavigationStyle.foregroundStyle(palette),
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    };
  }

  private static createTitleBar(title: string, palette: AppAppearancePalette,
    avoidLayoutSafeArea: boolean, enableComponentSafeArea: boolean,
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
        originalStyle: AppNavigationStyle.foregroundStyle(palette),
        scrollEffectStyle: AppNavigationStyle.foregroundStyle(palette),
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      }
    };
  }

  private static foregroundStyle(palette: AppAppearancePalette): HdsNavigationTitleBarStyle {
    const contentStyle: HdsTitleBarContentStyle = {
      titleStyle: {
        mainTitleColor: palette.titlePrimary,
        subTitleColor: palette.titleSecondary
      },
      menuStyle: {
        iconColor: palette.navigationActionForeground,
        textColor: palette.navigationActionForeground
      },
      backIconStyle: {
        iconColor: palette.navigationActionForeground,
        textColor: palette.navigationActionForeground
      },
      subIconStyle: {
        iconColor: palette.navigationActionForeground,
        textColor: palette.navigationActionForeground
      }
    };
    return { contentStyle: contentStyle };
  }
}
