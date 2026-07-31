import {
  HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions,
  IconStyleMode,
  TextStyleMode
} from '@kit.UIDesignKit';
import { ComponentContent, UIContext } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  MultiSelectActionMenu,
  MultiSelectActionMenuParams,
  MultiSelectController
} from '../library/MultiSelectController';
import { TitleBarMotionSpec } from './TitleBarMotionSpec';

export class SelectionNavigationTitleBar {
  private static animateState(uiContext: UIContext, change: () => void): void {
    uiContext.animateTo({
      curve: TitleBarMotionSpec.transitionCurve()
    }, change);
  }

  private static openActionMenu(
    uiContext: UIContext,
    controller: MultiSelectController,
    targetId: string
  ): void {
    const content = new ComponentContent(
      uiContext,
      wrapBuilder(MultiSelectActionMenu),
      new MultiSelectActionMenuParams(controller)
    );
    uiContext.getPromptAction().openMenu(
      content,
      { id: targetId },
      { enableArrow: true }
    ).catch((error: BusinessError): void => {
      console.warn(`Unable to open multi-select menu: ${error.code}, ${error.message}`);
    });
  }

  static menu(
    uiContext: UIContext,
    controller: MultiSelectController,
    targetId: string,
    revision: number,
    onStateChange: () => void,
    normalItems: Array<HdsNavigationMenuItemOptions> = [],
    selectionEnabled: boolean = true,
    onActivate: () => void = (): void => {}
  ): HdsNavigationMenuContentOptions {
    const effectiveTargetId = `${targetId}_${revision}`;
    controller.onStateChange = onStateChange;
    if (!selectionEnabled) {
      return { maxCount: normalItems.length, value: normalItems };
    }
    if (controller.active) {
      const activeItems: Array<HdsNavigationMenuItemOptions> = [{
        content: {
          label: controller.allSelected() ? '清空' : '全选',
          type: TextStyleMode.NORMAL,
          isEnabled: controller.selectableCount > 0 && !controller.busy,
          action: (): void =>
            SelectionNavigationTitleBar.animateState(uiContext, (): void => controller.toggleAll())
        }
      }, {
        content: {
          label: controller.selectedCount() > 0 ? `操作 ${controller.selectedCount()}` : '操作',
          type: TextStyleMode.NORMAL,
          componentId: effectiveTargetId,
          isEnabled: controller.selectedCount() > 0 && !controller.busy,
          action: (): void =>
            SelectionNavigationTitleBar.openActionMenu(uiContext, controller, effectiveTargetId)
        }
      }, {
        content: {
          label: '取消',
          type: TextStyleMode.NORMAL,
          action: (): void =>
            SelectionNavigationTitleBar.animateState(uiContext, (): void => controller.cancel())
        }
      }];
      return { maxCount: activeItems.length, value: activeItems };
    }
    const items = normalItems.concat([{
      content: {
        icon: $r('sys.symbol.checkmark_square_on_square'),
        label: '多选',
        type: IconStyleMode.NORMAL,
        action: (): void =>
          SelectionNavigationTitleBar.animateState(uiContext, (): void => {
            onActivate();
            controller.activate();
          })
      }
    }]);
    return { maxCount: items.length, value: items };
  }
}
