export class BundledArtworkCatalog {
  static readonly PREFIX: string = 'bundled-artwork://';

  static readonly DEFAULT_SMALL: string = 'bundled-artwork://default/small';
  static readonly DEFAULT_LARGE: string = 'bundled-artwork://default/large';
  static readonly DEFAULT_FULL: string = 'bundled-artwork://default/full';

  static readonly DEMO_CITY_SMALL: string = 'bundled-artwork://demo-city/small';
  static readonly DEMO_CITY_LARGE: string = 'bundled-artwork://demo-city/large';
  static readonly DEMO_CITY_FULL: string = 'bundled-artwork://demo-city/full';

  static readonly DEMO_COAST_SMALL: string = 'bundled-artwork://demo-coast/small';
  static readonly DEMO_COAST_LARGE: string = 'bundled-artwork://demo-coast/large';
  static readonly DEMO_COAST_FULL: string = 'bundled-artwork://demo-coast/full';

  static readonly DEMO_NIGHT_SMALL: string = 'bundled-artwork://demo-night/small';
  static readonly DEMO_NIGHT_LARGE: string = 'bundled-artwork://demo-night/large';
  static readonly DEMO_NIGHT_FULL: string = 'bundled-artwork://demo-night/full';

  static isPath(path: string): boolean {
    return path.startsWith(BundledArtworkCatalog.PREFIX);
  }

  static fullPath(path: string): string {
    if (!BundledArtworkCatalog.isPath(path)) {
      return path;
    }
    const variantSeparator = path.lastIndexOf('/');
    if (variantSeparator < BundledArtworkCatalog.PREFIX.length) {
      return path;
    }
    return `${path.substring(0, variantSeparator)}/full`;
  }

  static resolve(path: string): ResourceStr {
    switch (path) {
      case BundledArtworkCatalog.DEFAULT_SMALL:
        return $r('app.media.bundled_artwork_default_small');
      case BundledArtworkCatalog.DEFAULT_LARGE:
        return $r('app.media.bundled_artwork_default_large');
      case BundledArtworkCatalog.DEFAULT_FULL:
        return $r('app.media.bundled_artwork_default_full');
      case BundledArtworkCatalog.DEMO_CITY_SMALL:
        return $r('app.media.bundled_artwork_demo_city_small');
      case BundledArtworkCatalog.DEMO_CITY_LARGE:
        return $r('app.media.bundled_artwork_demo_city_large');
      case BundledArtworkCatalog.DEMO_CITY_FULL:
        return $r('app.media.bundled_artwork_demo_city_full');
      case BundledArtworkCatalog.DEMO_COAST_SMALL:
        return $r('app.media.bundled_artwork_demo_coast_small');
      case BundledArtworkCatalog.DEMO_COAST_LARGE:
        return $r('app.media.bundled_artwork_demo_coast_large');
      case BundledArtworkCatalog.DEMO_COAST_FULL:
        return $r('app.media.bundled_artwork_demo_coast_full');
      case BundledArtworkCatalog.DEMO_NIGHT_SMALL:
        return $r('app.media.bundled_artwork_demo_night_small');
      case BundledArtworkCatalog.DEMO_NIGHT_LARGE:
        return $r('app.media.bundled_artwork_demo_night_large');
      case BundledArtworkCatalog.DEMO_NIGHT_FULL:
        return $r('app.media.bundled_artwork_demo_night_full');
      default:
        return path;
    }
  }
}
