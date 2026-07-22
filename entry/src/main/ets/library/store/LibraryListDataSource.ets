export class LibraryListDataSource<T> implements IDataSource {
  private items: Array<T> = [];
  private readonly listeners: Array<DataChangeListener> = [];
  private revision: number = 0;

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  snapshot(): Array<T> {
    return this.items.slice();
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replace(items: Array<T>): void {
    const previousCount = this.items.length;
    this.items = items.slice();
    const nextCount = this.items.length;
    const revision = ++this.revision;
    const operations: Array<DataOperation> = [];
    const retainedCount = Math.min(previousCount, nextCount);
    for (let index = 0; index < retainedCount; index += 1) {
      operations.push({
        type: DataOperationType.CHANGE,
        index: index,
        key: `${revision}:${index}`
      });
    }
    if (nextCount > previousCount) {
      const keys: Array<string> = [];
      for (let index = previousCount; index < nextCount; index += 1) {
        keys.push(`${revision}:${index}`);
      }
      operations.push({
        type: DataOperationType.ADD,
        index: previousCount,
        count: nextCount - previousCount,
        key: keys
      });
    } else if (previousCount > nextCount) {
      operations.push({
        type: DataOperationType.DELETE,
        index: nextCount,
        count: previousCount - nextCount
      });
    }
    if (operations.length === 0) {
      return;
    }
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange(operations));
  }

  append(item: T): void {
    const index = this.items.length;
    this.items.push(item);
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataAdd(index));
  }

  clear(): void {
    const previousCount = this.items.length;
    if (previousCount === 0) {
      return;
    }
    this.items = [];
    const operations: Array<DataOperation> = [{
      type: DataOperationType.DELETE,
      index: 0,
      count: previousCount
    }];
    this.listeners.forEach((listener: DataChangeListener) => listener.onDatasetChange(operations));
  }
}
