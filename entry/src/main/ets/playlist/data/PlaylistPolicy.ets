import {
  PlaylistItemInput,
  PlaylistKind
} from '../../library/model/LibraryModels';

export const COMPLETED_HISTORY_FIXED_KEY = 'completed_history';
export const COMPLETED_HISTORY_NAME = '完整听过';

export interface PlaylistContentPlan {
  items: Array<PlaylistItemInput>;
  alreadyPresent: number;
  duplicateInput: number;
}

/**
 * Pure playlist invariants shared by persistence and UI.
 *
 * The completed-history entity is protected, but its membership deliberately
 * follows the same rules as a user playlist.
 */
export class PlaylistPolicy {
  static canCreate(kind: PlaylistKind): boolean {
    return kind === PlaylistKind.USER;
  }

  static canRename(kind: PlaylistKind): boolean {
    return kind === PlaylistKind.USER;
  }

  static canDelete(kind: PlaylistKind): boolean {
    return kind === PlaylistKind.USER;
  }

  static canEditItems(_kind: PlaylistKind): boolean {
    return true;
  }

  static normalizeName(name: string): string {
    return name.trim().replace(/\s+/g, ' ').toLowerCase();
  }

  static requireName(name: string): string {
    const normalized = PlaylistPolicy.normalizeName(name);
    if (normalized.length === 0) {
      throw new Error('Playlist name must not be empty');
    }
    return name.trim().replace(/\s+/g, ' ');
  }

  static planMerge(
    existingTrackIds: Array<number>,
    incoming: Array<PlaylistItemInput>
  ): PlaylistContentPlan {
    const existing = new Set<number>(existingTrackIds);
    const seen = new Set<number>();
    const items: Array<PlaylistItemInput> = [];
    let duplicateInput = 0;
    let alreadyPresent = 0;
    for (let index = 0; index < incoming.length; index += 1) {
      const item = incoming[index];
      if (seen.has(item.trackId)) {
        duplicateInput += 1;
        continue;
      }
      seen.add(item.trackId);
      if (existing.has(item.trackId)) {
        alreadyPresent += 1;
        continue;
      }
      items.push(item);
    }
    return {
      items: items,
      alreadyPresent: alreadyPresent,
      duplicateInput: duplicateInput
    };
  }

  static planReplace(incoming: Array<PlaylistItemInput>): PlaylistContentPlan {
    const seen = new Set<number>();
    const items: Array<PlaylistItemInput> = [];
    let duplicateInput = 0;
    for (let index = 0; index < incoming.length; index += 1) {
      const item = incoming[index];
      if (seen.has(item.trackId)) {
        duplicateInput += 1;
        continue;
      }
      seen.add(item.trackId);
      items.push(item);
    }
    return {
      items: items,
      alreadyPresent: 0,
      duplicateInput: duplicateInput
    };
  }

  static isCompleteReorder(currentTrackIds: Array<number>, reorderedTrackIds: Array<number>): boolean {
    if (currentTrackIds.length !== reorderedTrackIds.length) {
      return false;
    }
    const current = new Set<number>(currentTrackIds);
    if (current.size !== currentTrackIds.length) {
      return false;
    }
    const reordered = new Set<number>(reorderedTrackIds);
    if (reordered.size !== reorderedTrackIds.length || reordered.size !== current.size) {
      return false;
    }
    for (let index = 0; index < reorderedTrackIds.length; index += 1) {
      if (!current.has(reorderedTrackIds[index])) {
        return false;
      }
    }
    return true;
  }
}
