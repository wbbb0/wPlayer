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

export class SelectionNavigationTitleBar {
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
    normalItems: Array<HdsNavigationMenuItemOptions> = []
  ): HdsNavigationMenuContentOptions {
    const effectiveTargetId = `${targetId}_${revision}`;
    controller.onStateChange = onStateChange;
    if (controller.active) {
      const activeItems: Array<HdsNavigationMenuItemOptions> = [{
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
          action: (): void => controller.cancel()
        }
      }];
      return { maxCount: activeItems.length, value: activeItems };
    }
    const items = normalItems.concat([{
      content: {
        icon: $r('sys.symbol.checkmark_square_on_square'),
        label: '多选',
        type: IconStyleMode.NORMAL,
        action: (): void => controller.activate()
      }
    }]);
    return { maxCount: items.length, value: items };
  }
}
