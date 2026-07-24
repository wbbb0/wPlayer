import {
  HdsNavigationMenuContentOptions,
  HdsNavigationTitleBarStyle,
  HdsNavigationTitleBarOptions,
  HdsTitleBarContentStyle,
  ScrollEffectType,
  TitleBarStyleOptions,
  TitleBarContentOptions,
  hdsMaterial
} from '@kit.UIDesignKit';
import { ComponentContent } from '@kit.ArkUI';
import { AppPrimaryTitleParams } from './AppPrimaryTitleContent';

export interface AppNavigationColorOverride {
  backgroundColor: ResourceColor;
  contentColor: ResourceColor;
  controlBackgroundColor?: ResourceColor;
}

export class AppNavigationStyle {
  static primaryTitleBar(title: string, menu?: HdsNavigationMenuContentOptions,
    titleContent?: ComponentContent<AppPrimaryTitleParams>,
    gradientBackgroundColor?: ResourceColor): HdsNavigationTitleBarOptions {
    return AppNavigationStyle.createTitleBar(
      title,
      true,
      true,
      menu,
      titleContent,
      gradientBackgroundColor
    );
  }

  static secondaryTitleBar(title: string, menu?: HdsNavigationMenuContentOptions,
    gradientBackgroundColor?: ResourceColor): HdsNavigationTitleBarOptions {
    return AppNavigationStyle.createTitleBar(title, true, true, menu, undefined, gradientBackgroundColor);
  }

  static secondaryBackOnlyTitleBar(menu?: HdsNavigationMenuContentOptions,
    colors?: AppNavigationColorOverride): HdsNavigationTitleBarOptions {
    const style: TitleBarStyleOptions = {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: ScrollEffectType.GRADIENT_BLUR
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    };
    if (colors !== undefined) {
      style.originalStyle = AppNavigationStyle.colorStyle(colors);
      style.scrollEffectStyle = AppNavigationStyle.colorStyle(colors);
    }
    return {
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: { menu: menu },
      style: style
    };
  }

  private static createTitleBar(title: string, avoidLayoutSafeArea: boolean, enableComponentSafeArea: boolean,
    menu?: HdsNavigationMenuContentOptions,
    titleContent?: ComponentContent<AppPrimaryTitleParams>,
    gradientBackgroundColor?: ResourceColor): HdsNavigationTitleBarOptions {
    const content: TitleBarContentOptions = { menu: menu };
    if (titleContent === undefined) {
      content.title = { mainTitle: title };
    } else {
      content.stackBuilderComponent = titleContent;
    }
    const style: TitleBarStyleOptions = {
      scrollEffectOpts: {
        enableScrollEffect: true,
        scrollEffectType: ScrollEffectType.GRADIENT_BLUR
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    };
    if (gradientBackgroundColor !== undefined) {
      style.originalStyle = AppNavigationStyle.backgroundStyle(gradientBackgroundColor);
      style.scrollEffectStyle = AppNavigationStyle.backgroundStyle(gradientBackgroundColor);
    }
    return {
      avoidLayoutSafeArea: avoidLayoutSafeArea,
      enableComponentSafeArea: enableComponentSafeArea,
      content: content,
      style: style
    };
  }

  private static backgroundStyle(backgroundColor: ResourceColor): HdsNavigationTitleBarStyle {
    return {
      backgroundStyle: {
        backgroundColor: backgroundColor
      }
    };
  }

  private static colorStyle(colors: AppNavigationColorOverride): HdsNavigationTitleBarStyle {
    const contentStyle: HdsTitleBarContentStyle = {
      titleStyle: {
        mainTitleColor: colors.contentColor,
        subTitleColor: colors.contentColor
      },
      menuStyle: colors.controlBackgroundColor === undefined ? {
        iconColor: colors.contentColor,
        textColor: colors.contentColor
      } : {
        backgroundColor: colors.controlBackgroundColor,
        iconColor: colors.contentColor,
        textColor: colors.contentColor
      },
      backIconStyle: colors.controlBackgroundColor === undefined ? {
        iconColor: colors.contentColor,
        textColor: colors.contentColor
      } : {
        backgroundColor: colors.controlBackgroundColor,
        iconColor: colors.contentColor,
        textColor: colors.contentColor
      },
      subIconStyle: colors.controlBackgroundColor === undefined ? {
        iconColor: colors.contentColor,
        textColor: colors.contentColor
      } : {
        backgroundColor: colors.controlBackgroundColor,
        iconColor: colors.contentColor,
        textColor: colors.contentColor
      },
      dividerStyle: {
        dividerColor: colors.contentColor
      }
    };
    return {
      backgroundStyle: {
        backgroundColor: colors.backgroundColor
      },
      contentStyle: contentStyle
    };
  }

}
