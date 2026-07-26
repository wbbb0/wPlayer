export class DynamicBackgroundArtworkLoad {
  private generation: number = 0;
  private loadingUri: string = '';

  isLoading(uri: string): boolean {
    return uri.length > 0 && this.loadingUri === uri;
  }

  begin(uri: string): number {
    this.generation += 1;
    this.loadingUri = uri;
    return this.generation;
  }

  invalidateUnless(uri: string = ''): void {
    if (this.loadingUri.length === 0 || this.loadingUri === uri) {
      return;
    }
    this.generation += 1;
    this.loadingUri = '';
  }

  isCurrent(uri: string, generation: number): boolean {
    return generation === this.generation && uri === this.loadingUri;
  }

  finish(uri: string, generation: number): boolean {
    if (!this.isCurrent(uri, generation)) {
      return false;
    }
    this.loadingUri = '';
    return true;
  }

  cancel(): void {
    this.generation += 1;
    this.loadingUri = '';
  }
}
