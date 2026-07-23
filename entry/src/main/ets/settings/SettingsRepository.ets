import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { CompletedCollectionSettingPolicy } from './CompletedCollectionSettingPolicy';

const SETTINGS_FILE_NAME: string = 'wplayer_settings';
const LAST_TAB_INDEX_KEY: string = 'navigation.last_tab_index';
const LAST_NAVIGATION_ROUTE_KEY: string = 'navigation.last_route';
const NAVIGATION_ORDER_KEY: string = 'navigation.page_order';
const SONG_SORT_FIELD_KEY: string = 'library.songs.sort_field';
const SONG_SORT_DESCENDING_KEY: string = 'library.songs.sort_descending';
const ALBUM_SORT_FIELD_KEY: string = 'library.albums.sort_field';
const ALBUM_SORT_DESCENDING_KEY: string = 'library.albums.sort_descending';
const PLAYBACK_SHUFFLE_KEY: string = 'playback.shuffle_enabled';
const PLAYBACK_REPEAT_MODE_KEY: string = 'playback.repeat_mode';
const PLAYBACK_ARTWORK_WINDOW_KEY: string = 'playback.artwork_window_radius';
const PLAYBACK_LAST_TRACK_ID_KEY: string = 'playback.last_track_id';
const PLAYBACK_QUEUE_TRACK_IDS_KEY: string = 'playback.queue_track_ids';
const PLAYBACK_QUEUE_CURRENT_TRACK_ID_KEY: string = 'playback.queue_current_track_id';
const PLAYBACK_LAST_POSITION_MS_KEY: string = 'playback.last_position_ms';
const HIGH_QUALITY_HERO_ARTWORK_KEY: string = 'appearance.high_quality_hero_artwork';
const FOLLOW_PLAYBACK_THEME_KEY: string = 'appearance.follow_playback_theme';
const REMEMBER_PLAYBACK_POSITION_KEY: string = 'playback.remember_position';
const AUTO_RESUME_AFTER_OUTPUT_RECONNECT_KEY: string = 'playback.auto_resume_after_output_reconnect';
const REMEMBER_LAST_TAB_KEY: string = 'navigation.remember_last_tab';
const REMEMBER_LIBRARY_SORT_KEY: string = 'library.remember_sort';
const PRESERVE_SHUFFLE_ON_MANUAL_PLAY_KEY: string = 'playback.preserve_shuffle_on_manual_play';
const AUTO_REMOVE_UNAVAILABLE_ON_PLAYBACK_KEY: string = 'playback.auto_remove_unavailable';
const COMPLETED_COLLECTION_MODE_KEY: string = 'playback.completed_collection.mode';
const COMPLETED_COLLECTION_CURRENT_KEY: string = 'playback.completed_collection.current_enabled';
const RECENT_PLAYLIST_TARGET_IDS_KEY: string = 'playlist.recent_target_ids';
const DEMO_LIBRARY_ENABLED_KEY: string = 'debug.demo_library_enabled';

interface SettingUpdate {
  key: string;
  value: preferences.ValueType;
}

export class SettingsRepository {
  private readonly store: preferences.Preferences;

  constructor(context: common.Context) {
    this.store = preferences.getPreferencesSync(context, { name: SETTINGS_FILE_NAME });
    this.ensureDefaults();
  }

  getLastTabIndex(defaultValue: number = 0): number {
    return this.getNumber(LAST_TAB_INDEX_KEY, defaultValue);
  }

  setLastTabIndex(value: number): void {
    this.setValue(LAST_TAB_INDEX_KEY, value);
  }

  getLastNavigationRoute(defaultValue: string): string {
    return this.getString(LAST_NAVIGATION_ROUTE_KEY, defaultValue);
  }

  setLastNavigationRoute(value: string): void {
    this.setValue(LAST_NAVIGATION_ROUTE_KEY, value);
  }

  getNavigationOrder(defaultValue: Array<string>): Array<string> {
    try {
      const value = this.store.getSync(NAVIGATION_ORDER_KEY, defaultValue);
      if (!Array.isArray(value)) {
        return defaultValue;
      }
      const result: Array<string> = [];
      for (let index = 0; index < value.length; index += 1) {
        if (typeof value[index] === 'string') {
          result.push(value[index] as string);
        }
      }
      return result;
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to read setting ${NAVIGATION_ORDER_KEY}: ${businessError.code}, ${businessError.message}`);
      return defaultValue;
    }
  }

  setNavigationOrder(value: Array<string>): void {
    this.setValue(NAVIGATION_ORDER_KEY, value);
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

  getPlaybackShuffleEnabled(defaultValue: boolean = false): boolean {
    return this.getBoolean(PLAYBACK_SHUFFLE_KEY, defaultValue);
  }

  setPlaybackShuffleEnabled(value: boolean): void {
    this.setValue(PLAYBACK_SHUFFLE_KEY, value);
  }

  getPlaybackRepeatMode(defaultValue: number = 1): number {
    return this.getNumber(PLAYBACK_REPEAT_MODE_KEY, defaultValue);
  }

  setPlaybackRepeatMode(value: number): void {
    this.setValue(PLAYBACK_REPEAT_MODE_KEY, value);
  }

  getPlaybackArtworkWindowRadius(defaultValue: number = 2): number {
    return this.getNumber(PLAYBACK_ARTWORK_WINDOW_KEY, defaultValue);
  }

  getPlaybackLastTrackId(defaultValue: number = -1): number {
    return this.getNumber(PLAYBACK_LAST_TRACK_ID_KEY, defaultValue);
  }

  setPlaybackLastTrackId(value: number): void {
    this.setValue(PLAYBACK_LAST_TRACK_ID_KEY, value);
  }

  getPlaybackLastPositionMs(defaultValue: number = 0): number {
    return this.getNumber(PLAYBACK_LAST_POSITION_MS_KEY, defaultValue);
  }

  setPlaybackResumeState(trackId: number, positionMs: number): void {
    this.setValues([
      { key: PLAYBACK_LAST_TRACK_ID_KEY, value: trackId },
      { key: PLAYBACK_LAST_POSITION_MS_KEY, value: positionMs }
    ]);
  }

  getPlaybackQueueTrackIds(): Array<number> {
    try {
      const value = this.store.getSync(PLAYBACK_QUEUE_TRACK_IDS_KEY, []);
      if (!Array.isArray(value)) {
        return [];
      }
      const result: Array<number> = [];
      for (let index = 0; index < value.length; index += 1) {
        if (typeof value[index] === 'number') {
          result.push(value[index] as number);
        }
      }
      return result;
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to read setting ${PLAYBACK_QUEUE_TRACK_IDS_KEY}: ` +
        `${businessError.code}, ${businessError.message}`);
      return [];
    }
  }

  getPlaybackQueueCurrentTrackId(defaultValue: number = -1): number {
    return this.getNumber(PLAYBACK_QUEUE_CURRENT_TRACK_ID_KEY, defaultValue);
  }

  setPlaybackQueue(trackIds: Array<number>, currentTrackId: number): void {
    this.setValues([
      { key: PLAYBACK_QUEUE_TRACK_IDS_KEY, value: trackIds },
      { key: PLAYBACK_QUEUE_CURRENT_TRACK_ID_KEY, value: currentTrackId }
    ]);
  }

  getHighQualityHeroArtworkEnabled(defaultValue: boolean = true): boolean {
    return this.getBoolean(HIGH_QUALITY_HERO_ARTWORK_KEY, defaultValue);
  }

  setHighQualityHeroArtworkEnabled(value: boolean): void {
    this.setValue(HIGH_QUALITY_HERO_ARTWORK_KEY, value);
  }

  getFollowPlaybackThemeEnabled(defaultValue: boolean = true): boolean {
    return this.getBoolean(FOLLOW_PLAYBACK_THEME_KEY, defaultValue);
  }

  setFollowPlaybackThemeEnabled(value: boolean): void {
    this.setValue(FOLLOW_PLAYBACK_THEME_KEY, value);
  }

  getRememberPlaybackPositionEnabled(defaultValue: boolean = true): boolean {
    return this.getBoolean(REMEMBER_PLAYBACK_POSITION_KEY, defaultValue);
  }

  setRememberPlaybackPositionEnabled(value: boolean): void {
    this.setValue(REMEMBER_PLAYBACK_POSITION_KEY, value);
  }

  getAutoResumeAfterOutputReconnectEnabled(defaultValue: boolean = true): boolean {
    return this.getBoolean(AUTO_RESUME_AFTER_OUTPUT_RECONNECT_KEY, defaultValue);
  }

  setAutoResumeAfterOutputReconnectEnabled(value: boolean): void {
    this.setValue(AUTO_RESUME_AFTER_OUTPUT_RECONNECT_KEY, value);
  }

  getRememberLastTabEnabled(defaultValue: boolean = true): boolean {
    return this.getBoolean(REMEMBER_LAST_TAB_KEY, defaultValue);
  }

  setRememberLastTabEnabled(value: boolean): void {
    this.setValue(REMEMBER_LAST_TAB_KEY, value);
  }

  getRememberLibrarySortEnabled(defaultValue: boolean = true): boolean {
    return this.getBoolean(REMEMBER_LIBRARY_SORT_KEY, defaultValue);
  }

  setRememberLibrarySortEnabled(value: boolean): void {
    this.setValue(REMEMBER_LIBRARY_SORT_KEY, value);
  }

  getPreserveShuffleOnManualPlayEnabled(defaultValue: boolean = false): boolean {
    return this.getBoolean(PRESERVE_SHUFFLE_ON_MANUAL_PLAY_KEY, defaultValue);
  }

  setPreserveShuffleOnManualPlayEnabled(value: boolean): void {
    this.setValue(PRESERVE_SHUFFLE_ON_MANUAL_PLAY_KEY, value);
  }

  getAutoRemoveUnavailableOnPlaybackEnabled(defaultValue: boolean = false): boolean {
    return this.getBoolean(AUTO_REMOVE_UNAVAILABLE_ON_PLAYBACK_KEY, defaultValue);
  }

  setAutoRemoveUnavailableOnPlaybackEnabled(value: boolean): void {
    this.setValue(AUTO_REMOVE_UNAVAILABLE_ON_PLAYBACK_KEY, value);
  }

  getCompletedCollectionMode(defaultValue: number = 0): number {
    return this.getNumber(COMPLETED_COLLECTION_MODE_KEY, defaultValue);
  }

  setCompletedCollectionMode(value: number): void {
    this.setValue(COMPLETED_COLLECTION_MODE_KEY, value);
  }

  getCompletedCollectionCurrentEnabled(defaultValue: boolean = true): boolean {
    return this.getBoolean(COMPLETED_COLLECTION_CURRENT_KEY, defaultValue);
  }

  setCompletedCollectionCurrentEnabled(value: boolean): void {
    this.setValue(COMPLETED_COLLECTION_CURRENT_KEY, value);
  }

  getRecentPlaylistTargetIds(): Array<number> {
    try {
      const value = this.store.getSync(RECENT_PLAYLIST_TARGET_IDS_KEY, []);
      if (!Array.isArray(value)) {
        return [];
      }
      const result: Array<number> = [];
      for (let index = 0; index < value.length; index += 1) {
        if (typeof value[index] === 'number') {
          result.push(value[index] as number);
        }
      }
      return result;
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to read setting ${RECENT_PLAYLIST_TARGET_IDS_KEY}: ` +
        `${businessError.code}, ${businessError.message}`);
      return [];
    }
  }

  setRecentPlaylistTargetIds(value: Array<number>): void {
    this.setValue(RECENT_PLAYLIST_TARGET_IDS_KEY, value);
  }

  getDemoLibraryEnabled(defaultValue: boolean = false): boolean {
    return this.getBoolean(DEMO_LIBRARY_ENABLED_KEY, defaultValue);
  }

  setDemoLibraryEnabled(value: boolean): void {
    this.setValue(DEMO_LIBRARY_ENABLED_KEY, value);
  }

  private ensureDefaults(): void {
    try {
      const updates: Array<SettingUpdate> = [];
      const storedMode = this.store.getSync(COMPLETED_COLLECTION_MODE_KEY, 0);
      const completedMode = CompletedCollectionSettingPolicy.normalize(
        typeof storedMode === 'number' ? storedMode : 0
      );
      if (!this.store.hasSync(COMPLETED_COLLECTION_MODE_KEY) ||
        typeof storedMode !== 'number' || storedMode !== completedMode) {
        updates.push({ key: COMPLETED_COLLECTION_MODE_KEY, value: completedMode });
      }
      const storedEnabled = this.store.getSync(COMPLETED_COLLECTION_CURRENT_KEY, true);
      if (!this.store.hasSync(COMPLETED_COLLECTION_CURRENT_KEY) || typeof storedEnabled !== 'boolean') {
        updates.push({ key: COMPLETED_COLLECTION_CURRENT_KEY, value: true });
      }
      if (updates.length > 0) {
        this.setValues(updates);
      }
    } catch (error) {
      const businessError = error as BusinessError;
      console.warn(`Unable to initialize settings defaults: ${businessError.code}, ${businessError.message}`);
    }
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

  private getString(key: string, defaultValue: string): string {
    try {
      const value = this.store.getSync(key, defaultValue);
      return typeof value === 'string' ? value : defaultValue;
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
