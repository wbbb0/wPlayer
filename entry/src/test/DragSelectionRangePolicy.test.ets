import { describe, expect, it } from '@ohos/hypium';
import { DragSelectionRangePolicy } from '../main/ets/components/library/DragSelectionController';

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
  });
}
