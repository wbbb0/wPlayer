export class PlayerArtworkTapSequence {
  static readonly MAX_MOVEMENT: number = 8;
  private startX: number = 0;
  private startY: number = 0;
  private rejected: boolean = false;

  begin(x: number, y: number): void {
    this.startX = x;
    this.startY = y;
    this.rejected = false;
  }

  move(x: number, y: number): void {
    const dx = x - this.startX;
    const dy = y - this.startY;
    if (dx * dx + dy * dy >
      PlayerArtworkTapSequence.MAX_MOVEMENT * PlayerArtworkTapSequence.MAX_MOVEMENT) {
      this.rejected = true;
    }
  }

  cancel(): void {
    this.rejected = true;
  }

  allowsTap(): boolean {
    return !this.rejected;
  }
}
