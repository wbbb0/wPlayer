import {
  PlaylistSummary,
  TrackListItem
} from '../../library/model/LibraryModels';
import { PlaylistStore } from '../../playlist/store/PlaylistStore';
import { PlaylistSelectionPolicy } from '../../playlist/ui/PlaylistSelectionPolicy';
import { SettingsRepository } from '../../settings/SettingsRepository';
import { IndexPlaylistSheetKind } from './IndexPlaylistSheet';

@Observed
export class IndexPlaylistController {
  kind: IndexPlaylistSheetKind = IndexPlaylistSheetKind.CREATE;
  createName: string = '';
  pickerTrackIds: Array<number> = [];
  renameId: number = -1;
  renameName: string = '';
  recentPlaylistTargetIds: Array<number> = [];
  private settingsRepository?: SettingsRepository;
  private visibilityListener?: (visible: boolean) => void;
  private readonly store: PlaylistStore;

  constructor(store: PlaylistStore) {
    this.store = store;
  }

  bindVisibility(visibilityListener: (visible: boolean) => void): void {
    this.visibilityListener = visibilityListener;
  }

  bindSettings(settingsRepository?: SettingsRepository): void {
    this.settingsRepository = settingsRepository;
    if (settingsRepository === undefined) {
      return;
    }
    this.recentPlaylistTargetIds = PlaylistSelectionPolicy.recordRecentTarget(
      settingsRepository.getRecentPlaylistTargetIds(),
      -1
    );
  }

  dispose(): void {
    this.visibilityListener = undefined;
  }

  openCreator(): void {
    this.createName = '';
    this.open(IndexPlaylistSheetKind.CREATE);
  }

  saveNewPlaylist(): void {
    const name = this.createName.trim();
    if (name.length === 0 || this.store.mutating) {
      return;
    }
    this.store.create(name).then((created) => {
      if (created !== undefined) {
        this.close();
      }
    });
  }

  requestAddToPlaylist(items: Array<TrackListItem>): void {
    this.requestTrackIdsAddToPlaylist(
      items.map((item: TrackListItem): number => item.id)
    );
  }

  requestTrackIdsAddToPlaylist(ids: Array<number>): void {
    const trackIds = PlaylistSelectionPolicy.uniqueTrackIds(ids);
    if (trackIds.length === 0) {
      return;
    }
    this.pickerTrackIds = trackIds;
    this.open(IndexPlaylistSheetKind.PICKER);
  }

  recordRecentPlaylistTarget(playlistId: number): void {
    this.recentPlaylistTargetIds = PlaylistSelectionPolicy.recordRecentTarget(
      this.recentPlaylistTargetIds,
      playlistId
    );
    this.settingsRepository?.setRecentPlaylistTargetIds(this.recentPlaylistTargetIds);
  }

  openRenamer(playlist: PlaylistSummary): void {
    this.renameId = playlist.id;
    this.renameName = playlist.name;
    this.open(IndexPlaylistSheetKind.RENAME);
  }

  saveRename(): void {
    const name = this.renameName.trim();
    if (name.length === 0 || this.renameId < 0 || this.store.mutating) {
      return;
    }
    this.store.rename(this.renameId, name).then((renamed) => {
      if (renamed !== undefined) {
        this.close();
      }
    });
  }

  close(): void {
    this.visibilityListener?.(false);
  }

  sheetHeight(): SheetSize {
    return this.kind === IndexPlaylistSheetKind.PICKER ?
      SheetSize.LARGE : SheetSize.FIT_CONTENT;
  }

  private open(kind: IndexPlaylistSheetKind): void {
    this.kind = kind;
    this.visibilityListener?.(true);
  }
}
