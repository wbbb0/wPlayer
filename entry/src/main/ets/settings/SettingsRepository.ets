import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

const SETTINGS_FILE_NAME: string = 'wplayer_settings';
const LAST_TAB_INDEX_KEY: string = 'navigation.last_tab_index';
const SONG_SORT_FIELD_KEY: string = 'library.songs.sort_field';
const SONG_SORT_DESCENDING_KEY: string = 'library.songs.sort_descending';
const ALBUM_SORT_FIELD_KEY: string = 'library.albums.sort_field';
const ALBUM_SORT_DESCENDING_KEY: string = 'library.albums.sort_descending';

interface SettingUpdate {
  key: string;
  value: preferences.ValueType;
}

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

  getSongSortDescending(defaultValue: boolean = false): boolean {
    return this.getBoolean(SONG_SORT_DESCENDING_KEY, defaultValue);
  }

  setSongSort(field: number, descending: boolean): void {
    this.setValues([
      { key: SONG_SORT_FIELD_KEY, value: field },
      { key: SONG_SORT_DESCENDING_KEY, value: descending }
    ]);
  }

  getAlbumSortField(defaultValue: number = 0): number {
    return this.getNumber(ALBUM_SORT_FIELD_KEY, defaultValue);
  }

  getAlbumSortDescending(defaultValue: boolean = false): boolean {
    return this.getBoolean(ALBUM_SORT_DESCENDING_KEY, defaultValue);
  }

  setAlbumSort(field: number, descending: boolean): void {
    this.setValues([
      { key: ALBUM_SORT_FIELD_KEY, value: field },
      { key: ALBUM_SORT_DESCENDING_KEY, value: descending }
    ]);
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
    this.setValues([{ key: key, value: value }]);
  }

  private setValues(updates: Array<SettingUpdate>): void {
    try {
      for (let index = 0; index < updates.length; index += 1) {
        this.store.putSync(updates[index].key, updates[index].value);
      }
      this.store.flush().catch((error: BusinessError) => {
        console.warn(`Unable to persist settings: ${error.code}, ${error.message}`);
      });
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to update settings: ${businessError.code}, ${businessError.message}`);
    }
  }
}
