import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

const SETTINGS_FILE_NAME: string = 'wplayer_settings';
const LAST_TAB_INDEX_KEY: string = 'navigation.last_tab_index';
const SONG_SORT_FIELD_KEY: string = 'library.songs.sort_field';
const SONG_SORT_DESCENDING_KEY: string = 'library.songs.sort_descending';
const ALBUM_SORT_FIELD_KEY: string = 'library.albums.sort_field';
const ALBUM_SORT_DESCENDING_KEY: string = 'library.albums.sort_descending';

export class SettingsRepository {
  private readonly store: preferences.Preferences;

  constructor(context: common.Context) {
    this.store = preferences.getPreferencesSync(context, { name: SETTINGS_FILE_NAME });
  }

  getLastTabIndex(defaultValue: number = 0): number {
    return this.getNumber(LAST_TAB_INDEX_KEY, defaultValue);
  }

  setLastTabIndex(value: number): void {
    this.setValue(LAST_TAB_INDEX_KEY, value);
  }

  getSongSortField(defaultValue: number = 0): number {
    return this.getNumber(SONG_SORT_FIELD_KEY, defaultValue);
  }

  setSongSortField(value: number): void {
    this.setValue(SONG_SORT_FIELD_KEY, value);
  }

  getSongSortDescending(defaultValue: boolean = false): boolean {
    return this.getBoolean(SONG_SORT_DESCENDING_KEY, defaultValue);
  }

  setSongSortDescending(value: boolean): void {
    this.setValue(SONG_SORT_DESCENDING_KEY, value);
  }

  getAlbumSortField(defaultValue: number = 0): number {
    return this.getNumber(ALBUM_SORT_FIELD_KEY, defaultValue);
  }

  setAlbumSortField(value: number): void {
    this.setValue(ALBUM_SORT_FIELD_KEY, value);
  }

  getAlbumSortDescending(defaultValue: boolean = false): boolean {
    return this.getBoolean(ALBUM_SORT_DESCENDING_KEY, defaultValue);
  }

  setAlbumSortDescending(value: boolean): void {
    this.setValue(ALBUM_SORT_DESCENDING_KEY, value);
  }

  private getNumber(key: string, defaultValue: number): number {
    try {
      const value = this.store.getSync(key, defaultValue);
      return typeof value === 'number' ? value : defaultValue;
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to read setting ${key}: ${businessError.code}, ${businessError.message}`);
      return defaultValue;
    }
  }

  private getBoolean(key: string, defaultValue: boolean): boolean {
    try {
      const value = this.store.getSync(key, defaultValue);
      return typeof value === 'boolean' ? value : defaultValue;
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to read setting ${key}: ${businessError.code}, ${businessError.message}`);
      return defaultValue;
    }
  }

  private setValue(key: string, value: preferences.ValueType): void {
    try {
      this.store.putSync(key, value);
      this.store.flush().catch((error: BusinessError) => {
        console.warn(`Unable to persist setting ${key}: ${error.code}, ${error.message}`);
      });
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to update setting ${key}: ${businessError.code}, ${businessError.message}`);
    }
  }
}
