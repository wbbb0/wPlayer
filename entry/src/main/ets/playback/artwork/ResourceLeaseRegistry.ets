export class ResourceLeaseRegistry<T extends Object> {
  private readonly leases: Map<T, number> = new Map();
  private readonly pendingRelease: Set<T> = new Set();
  private readonly releaseResource: (resource: T) => void;

  constructor(releaseResource: (resource: T) => void) {
    this.releaseResource = releaseResource;
  }

  acquire(resource: T): void {
    this.leases.set(resource, (this.leases.get(resource) ?? 0) + 1);
  }

  release(resource: T): void {
    const count = this.leases.get(resource) ?? 0;
    if (count <= 1) {
      this.leases.delete(resource);
      if (this.pendingRelease.delete(resource)) {
        this.releaseResource(resource);
      }
      return;
    }
    this.leases.set(resource, count - 1);
  }

  requestRelease(resource: T): void {
    if ((this.leases.get(resource) ?? 0) > 0) {
      this.pendingRelease.add(resource);
      return;
    }
    this.releaseResource(resource);
  }

  isLeased(resource: T): boolean {
    return (this.leases.get(resource) ?? 0) > 0;
  }
}
