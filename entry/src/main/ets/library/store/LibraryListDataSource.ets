export class LibraryListDataSource<T> implements IDataSource {
  private items: Array<T> = [];
  private readonly listeners: Array<DataChangeListener> = [];

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
    this.items = items.slice();
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }

  append(item: T): void {
    const index = this.items.length;
    this.items.push(item);
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataAdd(index));
  }

  clear(): void {
    if (this.items.length === 0) {
      return;
    }
    this.items = [];
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}
