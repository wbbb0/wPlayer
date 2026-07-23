import { describe, expect, it } from '@ohos/hypium';
import { LibraryListDataSource } from '../main/ets/library/store/LibraryListDataSource';

class ListTestItem {
  id: number = 0;
  label: string = '';
}

class RecordingDataChangeListener implements DataChangeListener {
  operations: Array<DataOperation> = [];

  onDataReloaded(): void {}
  onDataAdded(_index: number): void {}
  onDataAdd(_index: number): void {}
  onDataMoved(_from: number, _to: number): void {}
  onDataMove(_from: number, _to: number): void {}
  onDataDeleted(_index: number): void {}
  onDataDelete(_index: number): void {}
  onDataChanged(_index: number): void {}
  onDataChange(_index: number): void {}

  onDatasetChange(dataOperations: Array<DataOperation>): void {
    this.operations = dataOperations;
  }
}

function item(id: number, label: string): ListTestItem {
  const value = new ListTestItem();
  value.id = id;
  value.label = label;
  return value;
}

export default function libraryListDataSourceTest() {
  describe('LibraryListDataSource', () => {
    it('marks retained positions changed when replacement data has new fields', 0, () => {
      const source = new LibraryListDataSource<ListTestItem>();
      const listener = new RecordingDataChangeListener();
      source.registerDataChangeListener(listener);

      source.replace([item(1, '49')]);
      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.ADD);

      source.replace([item(1, '19')]);
      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.CHANGE);
      expect(source.getData(0).label).assertEqual('19');
    });

    it('combines retained changes with tail additions and deletions', 0, () => {
      const source = new LibraryListDataSource<ListTestItem>();
      const listener = new RecordingDataChangeListener();
      source.registerDataChangeListener(listener);

      source.replace([item(1, 'a'), item(2, 'b')]);
      source.replace([item(2, 'b2'), item(1, 'a2'), item(3, 'c')]);
      expect(listener.operations.length).assertEqual(3);
      expect(listener.operations[0].type).assertEqual(DataOperationType.CHANGE);
      expect(listener.operations[1].type).assertEqual(DataOperationType.CHANGE);
      expect(listener.operations[2].type).assertEqual(DataOperationType.ADD);

      source.replace([item(2, 'b3')]);
      expect(listener.operations.length).assertEqual(2);
      expect(listener.operations[0].type).assertEqual(DataOperationType.CHANGE);
      expect(listener.operations[1].type).assertEqual(DataOperationType.DELETE);
      expect(source.totalCount()).assertEqual(1);
    });

    it('returns an isolated snapshot for selection and playback operations', 0, () => {
      const source = new LibraryListDataSource<ListTestItem>();
      source.replace([item(1, 'one'), item(2, 'two')]);

      const snapshot = source.snapshot();
      snapshot.pop();

      expect(snapshot.length).assertEqual(1);
      expect(source.totalCount()).assertEqual(2);
      expect(source.getData(1).label).assertEqual('two');
    });
  });
}
