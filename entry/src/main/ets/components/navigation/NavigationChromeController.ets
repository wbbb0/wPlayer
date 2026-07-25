import { systemBarStyleController } from '../../appearance/SystemBarStyleController';

export const NAVIGATION_SYSTEM_BAR_OWNER: string = 'hds_navigation_root';

class NavigationAlbumChromeEntry {
  readonly routeId: string;
  readonly instanceId: number;
  readonly backgroundColor: string;
  readonly contentColor: string;
  readonly visibilityCount: number;

  constructor(
    routeId: string,
    instanceId: number,
    backgroundColor: string,
    contentColor: string,
    visibilityCount: number = 1
  ) {
    this.routeId = routeId;
    this.instanceId = instanceId;
    this.backgroundColor = backgroundColor;
    this.contentColor = contentColor;
    this.visibilityCount = visibilityCount;
  }
}

@Observed
export class NavigationChromeController {
  activeRouteId: string = '';
  activeAlbumInstanceId: number = -1;
  activeAlbumBackgroundColor: string = '';
  activeAlbumContentColor: string = '';
  private albumEntries: Array<NavigationAlbumChromeEntry> = [];
  private attached: boolean = false;

  attach(): void {
    if (this.attached) {
      return;
    }
    this.attached = true;
    this.syncActiveEntry();
  }

  dispose(): void {
    this.attached = false;
    systemBarStyleController.removeContentColor(NAVIGATION_SYSTEM_BAR_OWNER);
    this.albumEntries = [];
    this.activeRouteId = '';
    this.activeAlbumInstanceId = -1;
    this.activeAlbumBackgroundColor = '';
    this.activeAlbumContentColor = '';
  }

  setActiveRoute(routeId: string): void {
    if (this.activeRouteId === routeId) {
      return;
    }
    this.activeRouteId = routeId;
    this.syncActiveEntry();
  }

  registerAlbum(
    routeId: string,
    instanceId: number,
    backgroundColor: string,
    contentColor: string
  ): void {
    const index = this.albumEntryIndex(routeId);
    if (index >= 0 && this.albumEntries[index].instanceId === instanceId) {
      this.albumEntries[index] = new NavigationAlbumChromeEntry(
        routeId,
        instanceId,
        backgroundColor,
        contentColor,
        this.albumEntries[index].visibilityCount + 1
      );
    } else {
      const entry = new NavigationAlbumChromeEntry(
        routeId,
        instanceId,
        backgroundColor,
        contentColor
      );
      if (index >= 0) {
        this.albumEntries[index] = entry;
      } else {
        this.albumEntries.push(entry);
      }
    }
    if (routeId === this.activeRouteId) {
      this.syncActiveEntry();
    }
  }

  updateAlbum(
    routeId: string,
    instanceId: number,
    backgroundColor: string,
    contentColor: string
  ): void {
    const index = this.albumEntryIndex(routeId);
    if (index < 0 || this.albumEntries[index].instanceId !== instanceId) {
      return;
    }
    this.albumEntries[index] = new NavigationAlbumChromeEntry(
      routeId,
      instanceId,
      backgroundColor,
      contentColor,
      this.albumEntries[index].visibilityCount
    );
    if (routeId === this.activeRouteId) {
      this.syncActiveEntry();
    }
  }

  unregisterAlbum(routeId: string, instanceId: number): void {
    const index = this.albumEntryIndex(routeId);
    if (index < 0 || this.albumEntries[index].instanceId !== instanceId) {
      return;
    }
    const entry = this.albumEntries[index];
    if (entry.visibilityCount > 1) {
      this.albumEntries[index] = new NavigationAlbumChromeEntry(
        entry.routeId,
        entry.instanceId,
        entry.backgroundColor,
        entry.contentColor,
        entry.visibilityCount - 1
      );
    } else {
      this.albumEntries.splice(index, 1);
    }
    if (routeId === this.activeRouteId) {
      this.syncActiveEntry();
    }
  }

  clearRoute(routeId: string): void {
    const index = this.albumEntryIndex(routeId);
    if (index < 0) {
      return;
    }
    this.albumEntries.splice(index, 1);
    if (routeId === this.activeRouteId) {
      this.syncActiveEntry();
    }
  }

  hasActiveAlbum(): boolean {
    return this.activeAlbumInstanceId >= 0 && this.activeAlbumBackgroundColor.length > 0;
  }

  private albumEntryIndex(routeId: string): number {
    for (let index = 0; index < this.albumEntries.length; index += 1) {
      if (this.albumEntries[index].routeId === routeId) {
        return index;
      }
    }
    return -1;
  }

  private activeAlbumEntry(): NavigationAlbumChromeEntry | undefined {
    const index = this.albumEntryIndex(this.activeRouteId);
    return index >= 0 ? this.albumEntries[index] : undefined;
  }

  private syncActiveEntry(): void {
    const entry = this.activeAlbumEntry();
    this.activeAlbumInstanceId = entry?.instanceId ?? -1;
    this.activeAlbumBackgroundColor = entry?.backgroundColor ?? '';
    this.activeAlbumContentColor = entry?.contentColor ?? '';
    if (this.attached) {
      systemBarStyleController.submitContentColor(
        NAVIGATION_SYSTEM_BAR_OWNER,
        entry?.contentColor
      );
    }
  }
}
