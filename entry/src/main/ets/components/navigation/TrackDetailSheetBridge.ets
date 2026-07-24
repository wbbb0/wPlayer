import { TrackListItem } from '../../library/model/LibraryModels';

export class TrackDetailSheetBridge {
  private handler?: (track: TrackListItem) => void;

  attach(handler: (track: TrackListItem) => void): void {
    this.handler = handler;
  }

  detach(handler: (track: TrackListItem) => void): void {
    if (this.handler === handler) {
      this.handler = undefined;
    }
  }

  open(track: TrackListItem): void {
    this.handler?.(track);
  }
}
