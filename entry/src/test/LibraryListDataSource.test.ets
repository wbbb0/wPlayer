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
    it('publishes one reload when replacement data has new fields', 0, () => {
      const source = new LibraryListDataSource<ListTestItem>();
      const listener = new RecordingDataChangeListener();
      source.registerDataChangeListener(listener);

      source.replace([item(1, '49')]);
      const initialKey = source.keyFor(1);
      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.RELOAD);
      expect(source.keyFor(1)).assertEqual(initialKey);
      expect(source.keyFor(2) === initialKey).assertFalse();

      source.replace([item(1, '19')]);
      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.RELOAD);
      expect(source.keyFor(1) === initialKey).assertFalse();
      expect(source.getData(0).label).assertEqual('19');
    });

    it('keeps replacement notifications bounded for large lists', 0, () => {
      const source = new LibraryListDataSource<ListTestItem>();
      const listener = new RecordingDataChangeListener();
      source.registerDataChangeListener(listener);

      const items: Array<ListTestItem> = [];
      for (let index = 0; index < 59000; index += 1) {
        items.push(item(index, `${index}`));
      }
      source.replace(items);

      expect(listener.operations.length).assertEqual(1);
      expect(listener.operations[0].type).assertEqual(DataOperationType.RELOAD);
      expect(source.totalCount()).assertEqual(59000);
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
