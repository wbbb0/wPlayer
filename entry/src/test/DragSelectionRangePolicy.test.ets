import { describe, expect, it } from '@ohos/hypium';
import {
  DragSelectionController,
  DragSelectionHitMode,
  DragSelectionRangePolicy
} from '../main/ets/components/library/DragSelectionController';

function targetArea(top: number): Area {
  return {
    width: 10,
    height: 10,
    position: { x: 0, y: top },
    globalPosition: { x: 0, y: top }
  } as Area;
}

export default function dragSelectionRangePolicyTest() {
  describe('Drag selection range policy', () => {
    it('shrinks the pending range when the pointer moves back toward its anchor', 0, () => {
      expect(DragSelectionRangePolicy.includes(4, 1, 5)).assertTrue();
      expect(DragSelectionRangePolicy.includes(4, 1, 3)).assertFalse();
      expect(DragSelectionRangePolicy.includes(3, 1, 3)).assertTrue();
    });

    it('uses display order so a grid range includes complete intervening cells', 0, () => {
      const included: Array<number> = [];
      for (let order = 0; order < 6; order += 1) {
        if (DragSelectionRangePolicy.includes(order, 0, 4)) {
          included.push(order);
        }
      }
      expect(included.length).assertEqual(5);
      expect(included[4]).assertEqual(4);
    });

    it('remaps cached targets before the next drag session', 0, () => {
      const applied: Array<number> = [];
      const controller = new DragSelectionController();
      controller.updateTarget(1, 1, 0, targetArea(0), DragSelectionHitMode.ROW,
        (): boolean => false, (): void => { applied.push(1); });
      controller.updateTarget(2, 2, 1, targetArea(20), DragSelectionHitMode.ROW,
        (): boolean => false, (): void => { applied.push(2); });
      controller.updateTarget(3, 3, 2, targetArea(40), DragSelectionHitMode.ROW,
        (): boolean => false, (): void => { applied.push(3); });
      controller.remapTargets((id: number): number => {
        if (id === 1) {
          return 2;
        }
        return id === 2 ? 0 : 1;
      });

      controller.start(1);
      controller.update(5, 25);
      controller.end();

      expect(applied.sort((left: number, right: number): number => left - right).join(','))
        .assertEqual('1,2,3');
    });
  });
}
