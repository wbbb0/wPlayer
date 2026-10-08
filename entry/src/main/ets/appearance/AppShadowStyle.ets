export class AppShadowStyle {
  static radius(radius: number, enabled: boolean = true): number {
    // API 26 renders an unblurred offset shadow at zero; negative means no shadow.
    return enabled && Number.isFinite(radius) && radius > 0 ? radius : -1;
  }
}
