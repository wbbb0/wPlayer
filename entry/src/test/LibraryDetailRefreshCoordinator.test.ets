import { describe, expect, it } from '@ohos/hypium';
import {
  LibraryDetailContentSource, LibraryDetailRefreshCoordinator, LibraryDetailRefreshTarget
} from '../main/ets/library/store/LibraryDetailRefreshCoordinator';

class DetailContentSource implements LibraryDetailContentSource {
  libraryContentRevision: number = 0;
  listeners: Array<() => void> = [];

  addContentChangeListener(listener: () => void): void {
    this.listeners.push(listener);
  }

  removeContentChangeListener(listener: () => void): void {
    this.listeners = this.listeners.filter((candidate: () => void): boolean => candidate !== listener);
  }

  change(): void {
    this.libraryContentRevision += 1;
    this.listeners.slice().forEach((listener: () => void): void => listener());
  }
}

class DetailRefreshTarget<T> implements LibraryDetailRefreshTarget<T> {
  loading: boolean = false;
  error: string = '';
  values: Array<T> = [];
  onCommit?: (value: T) => void;

  commitDetail(value: T): void {
    this.values.push(value);
    this.onCommit?.(value);
  }
}

export default function libraryDetailRefreshCoordinatorTest() {
  describe('Retained library detail revisions', () => {
    it('reuses an unchanged cache and refreshes changes made while hidden', 0, async () => {
      const source = new DetailContentSource();
      const target = new DetailRefreshTarget<number>();
      let reads = 0;
      const read = async (): Promise<number> => { reads += 1; return source.libraryContentRevision; };
      const coordinator = new LibraryDetailRefreshCoordinator<number>();
      await coordinator.activate(source, read, target);
      coordinator.deactivate(source);
      await coordinator.activate(source, read, target);
      expect(reads).assertEqual(1);
      coordinator.deactivate(source);
      source.change();
      await coordinator.activate(source, read, target);
      expect(reads).assertEqual(2);
      expect(target.values.join(',')).assertEqual('0,1');
      expect(source.listeners.length).assertEqual(1);
      coordinator.deactivate(source);
      expect(source.listeners.length).assertEqual(0);
    });

    it('coalesces changes during a read and never publishes an obsolete snapshot', 0, async () => {
      const source = new DetailContentSource();
      const target = new DetailRefreshTarget<number>();
      let reads = 0;
      let finish: (value: number) => void = (_value: number): void => {};
      const oldRead = new Promise<number>((resolve): void => { finish = resolve; });
      const coordinator = new LibraryDetailRefreshCoordinator<number>();
      const loading = coordinator.activate(source, (): Promise<number> => {
        reads += 1;
        return reads === 1 ? oldRead : Promise.resolve(source.libraryContentRevision);
      }, target);
      source.change();
      source.change();
      finish(0);
      await loading;
      expect(target.values.join(',')).assertEqual('2');
      expect(reads).assertEqual(2);
      coordinator.deactivate(source);
    });

    it('rejects completion after leaving and retries after a failed read', 0, async () => {
      const source = new DetailContentSource();
      const target = new DetailRefreshTarget<number>();
      let finish: (value: number) => void = (_value: number): void => {};
      const coordinator = new LibraryDetailRefreshCoordinator<number>();
      const oldRead = coordinator.activate(source, (): Promise<number> => new Promise<number>((resolve): void => {
        finish = resolve;
      }), target);
      coordinator.deactivate(source);
      await coordinator.activate(source, async (): Promise<number> => { throw new Error('query failed'); }, target);
      finish(99);
      await oldRead;
      expect(target.values.length).assertEqual(0);
      expect(target.error).assertEqual('query failed');
      expect(target.loading).assertFalse();
      coordinator.deactivate(source);
      await coordinator.activate(source, async (): Promise<number> => 2, target);
      expect(target.values.join(',')).assertEqual('2');
      expect(target.error).assertEqual('');
      coordinator.deactivate(source);
    });

    it('drains a change arriving between publication and promise completion', 0, async () => {
      const source = new DetailContentSource();
      const target = new DetailRefreshTarget<number>();
      target.onCommit = (value: number): void => {
        if (value === 0) {
          source.change();
        }
      };
      const coordinator = new LibraryDetailRefreshCoordinator<number>();
      const read = async (): Promise<number> => source.libraryContentRevision;
      await coordinator.activate(source, read, target);
      await coordinator.activate(source, read, target);
      expect(target.values.join(',')).assertEqual('0,1');
      coordinator.deactivate(source);
    });

    it('publishes an empty result when the underlying entity is removed', 0, async () => {
      const source = new DetailContentSource();
      const target = new DetailRefreshTarget<number | undefined>();
      let present = true;
      const coordinator = new LibraryDetailRefreshCoordinator<number | undefined>();
      const read = async (): Promise<number | undefined> => present ? 7 : undefined;
      await coordinator.activate(source, read, target);
      present = false;
      source.change();
      await coordinator.activate(source, read, target);
      expect(target.values.length).assertEqual(2);
      expect(target.values[1]).assertUndefined();
      expect(target.loading).assertFalse();
      coordinator.deactivate(source);
    });

    it('publishes loading, result and failure through the activation target', 0, async () => {
      const source = new DetailContentSource();
      const target = new DetailRefreshTarget<number>();
      target.error = 'previous failure';
      let finish: (value: number) => void = (_value: number): void => {};
      const coordinator = new LibraryDetailRefreshCoordinator<number>();
      const pending = coordinator.activate(source, (): Promise<number> => new Promise<number>((resolve): void => {
        finish = resolve;
      }), target);
      expect(target.loading).assertTrue();
      expect(target.error).assertEqual('');
      finish(7);
      await pending;
      expect(target.values.join(',')).assertEqual('7');
      expect(target.loading).assertFalse();
      await coordinator.refresh(source, async (): Promise<number> => { throw new Error('read failed'); }, target);
      expect(target.error).assertEqual('read failed');
      expect(target.loading).assertFalse();
      expect(target.values.join(',')).assertEqual('7');
      coordinator.deactivate(source);
    });

    it('invalidates an old target and reloads an unchanged source for its replacement', 0, async () => {
      const source = new DetailContentSource();
      const oldTarget = new DetailRefreshTarget<number>();
      const nextTarget = new DetailRefreshTarget<number>();
      let finish: (value: number) => void = (_value: number): void => {};
      const coordinator = new LibraryDetailRefreshCoordinator<number>();
      const oldRead = coordinator.activate(source, (): Promise<number> => new Promise<number>((resolve): void => {
        finish = resolve;
      }), oldTarget);
      await coordinator.activate(source, async (): Promise<number> => 2, nextTarget);
      finish(99);
      await oldRead;
      expect(oldTarget.loading).assertFalse();
      expect(oldTarget.values.length).assertEqual(0);
      expect(nextTarget.values.join(',')).assertEqual('2');
      expect(nextTarget.loading).assertFalse();
      await coordinator.activate(source, async (): Promise<number> => 3, oldTarget);
      expect(oldTarget.values.join(',')).assertEqual('3');
      expect(source.listeners.length).assertEqual(1);
      coordinator.deactivate(source);
    });
  });
}
