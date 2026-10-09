import { describe, expect, it } from '@ohos/hypium';
import {
  LibraryDetailContentSource, LibraryDetailRefreshCoordinator
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

export default function libraryDetailRefreshCoordinatorTest() {
  describe('Retained library detail revisions', () => {
    it('reuses an unchanged cache and refreshes changes made while hidden', 0, async () => {
      const source = new DetailContentSource();
      let reads = 0;
      let displayed = -1;
      const read = async (): Promise<number> => { reads += 1; return source.libraryContentRevision; };
      const coordinator = new LibraryDetailRefreshCoordinator<number>(
        (value: number): void => { displayed = value; }, (_loading: boolean): void => {},
        (_error: string): void => {}
      );
      await coordinator.activate(source, read);
      coordinator.deactivate(source);
      await coordinator.activate(source, read);
      expect(reads).assertEqual(1);
      coordinator.deactivate(source);
      source.change();
      await coordinator.activate(source, read);
      expect(reads).assertEqual(2);
      expect(displayed).assertEqual(1);
      expect(source.listeners.length).assertEqual(1);
      coordinator.deactivate(source);
      expect(source.listeners.length).assertEqual(0);
    });

    it('coalesces changes during a read and never publishes an obsolete snapshot', 0, async () => {
      const source = new DetailContentSource();
      const displayed: Array<number> = [];
      let reads = 0;
      let finish: (value: number) => void = (_value: number): void => {};
      const oldRead = new Promise<number>((resolve): void => { finish = resolve; });
      const coordinator = new LibraryDetailRefreshCoordinator<number>(
        (value: number): void => { displayed.push(value); }, (_loading: boolean): void => {},
        (_error: string): void => {}
      );
      const loading = coordinator.activate(source, (): Promise<number> => {
        reads += 1;
        return reads === 1 ? oldRead : Promise.resolve(source.libraryContentRevision);
      });
      source.change();
      source.change();
      finish(0);
      await loading;
      expect(displayed.join(',')).assertEqual('2');
      expect(reads).assertEqual(2);
      coordinator.deactivate(source);
    });

    it('rejects completion after leaving and retries after a failed read', 0, async () => {
      const source = new DetailContentSource();
      const displayed: Array<number> = [];
      let finish: (value: number) => void = (_value: number): void => {};
      let loading = false;
      let error = '';
      const coordinator = new LibraryDetailRefreshCoordinator<number>(
        (value: number): void => { displayed.push(value); },
        (value: boolean): void => { loading = value; }, (message: string): void => { error = message; }
      );
      const oldRead = coordinator.activate(source, (): Promise<number> => new Promise<number>((resolve): void => {
        finish = resolve;
      }));
      coordinator.deactivate(source);
      await coordinator.activate(source, async (): Promise<number> => { throw new Error('query failed'); });
      finish(99);
      await oldRead;
      expect(displayed.length).assertEqual(0);
      expect(error).assertEqual('query failed');
      expect(loading).assertFalse();
      coordinator.deactivate(source);
      await coordinator.activate(source, async (): Promise<number> => 2);
      expect(displayed.join(',')).assertEqual('2');
      expect(error).assertEqual('');
      coordinator.deactivate(source);
    });

    it('drains a change arriving between publication and promise completion', 0, async () => {
      const source = new DetailContentSource();
      const displayed: Array<number> = [];
      const coordinator = new LibraryDetailRefreshCoordinator<number>(
        (value: number): void => {
          displayed.push(value);
          if (value === 0) {
            source.change();
          }
        }, (_loading: boolean): void => {}, (_error: string): void => {}
      );
      const read = async (): Promise<number> => source.libraryContentRevision;
      await coordinator.activate(source, read);
      await coordinator.activate(source, read);
      expect(displayed.join(',')).assertEqual('0,1');
      coordinator.deactivate(source);
    });

    it('publishes an empty result when the underlying entity is removed', 0, async () => {
      const source = new DetailContentSource();
      let present = true;
      let displayed: number | undefined = 7;
      const coordinator = new LibraryDetailRefreshCoordinator<number | undefined>(
        (value: number | undefined): void => { displayed = value; }, (_loading: boolean): void => {},
        (_error: string): void => {}
      );
      const read = async (): Promise<number | undefined> => present ? 7 : undefined;
      await coordinator.activate(source, read);
      present = false;
      source.change();
      await coordinator.activate(source, read);
      expect(displayed).assertUndefined();
      coordinator.deactivate(source);
    });
  });
}
