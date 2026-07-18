export class PlaylistSelectionPolicy {
  static uniqueTrackIds(ids: Array<number>): Array<number> {
    return PlaylistSelectionPolicy.uniquePositiveIds(ids);
  }

  private static uniquePositiveIds(ids: Array<number>): Array<number> {
    const seen: Set<number> = new Set<number>();
    const result: Array<number> = [];
    for (let index = 0; index < ids.length; index += 1) {
      const id = ids[index];
      if (id <= 0 || seen.has(id)) {
        continue;
      }
      seen.add(id);
      result.push(id);
    }
    return result;
  }

  static recordRecentTarget(
    currentIds: Array<number>,
    playlistId: number,
    limit: number = 3
  ): Array<number> {
    if (playlistId <= 0 || limit <= 0) {
      return PlaylistSelectionPolicy.uniquePositiveIds(currentIds).slice(0, Math.max(0, limit));
    }
    const result: Array<number> = [playlistId];
    const current = PlaylistSelectionPolicy.uniquePositiveIds(currentIds);
    for (let index = 0; index < current.length && result.length < limit; index += 1) {
      if (current[index] !== playlistId) {
        result.push(current[index]);
      }
    }
    return result;
  }
}
