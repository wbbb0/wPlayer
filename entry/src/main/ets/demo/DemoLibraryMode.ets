import BuildProfile from 'entry/BuildProfile';

/**
 * Process-local switch for the screenshot/demo catalog.
 *
 * The value is always false in non-debug builds, even if a stale preference
 * remains on a device that previously ran a debug package.
 */
export class DemoLibraryMode {
  private static enabled: boolean = false;

  static isAvailable(): boolean {
    return BuildProfile.DEBUG;
  }

  static isEnabled(): boolean {
    return BuildProfile.DEBUG && DemoLibraryMode.enabled;
  }

  static setEnabled(enabled: boolean): void {
    DemoLibraryMode.enabled = BuildProfile.DEBUG && enabled;
  }
}
