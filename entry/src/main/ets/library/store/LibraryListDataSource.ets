export class LibraryListDataSource<T> implements IDataSource {
  private items: Array<T> = [];
  private readonly listeners: Array<DataChangeListener> = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
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
    this.items = items.slice();
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}
