import { SortDirection, TrackSortField } from '../model/LibraryModels';

export interface TrackProjectionSnapshot {
  generation: number;
  field: TrackSortField;
  direction: SortDirection;
}

/** Tracks the sort descriptor belonging to the currently published track catalog. */
export class LibraryTrackProjection {
  private generation: number = 0;
  private field: TrackSortField = TrackSortField.TITLE;
  private direction: SortDirection = SortDirection.ASCENDING;

  publish(field: TrackSortField, direction: SortDirection): void {
    this.field = field;
    this.direction = direction;
    this.generation += 1;
  }

  snapshot(): TrackProjectionSnapshot {
    return {
      generation: this.generation,
      field: this.field,
      direction: this.direction
    };
  }

  isCurrent(snapshot: TrackProjectionSnapshot): boolean {
    return snapshot.generation === this.generation;
  }
}
