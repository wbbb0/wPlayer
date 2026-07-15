export enum PreparedItemState {
  READY,
  DUPLICATE,
  FAILED
}

export class ImportPreparationPolicy {
  static classify(failed: boolean, duplicate: boolean, hasInput: boolean): PreparedItemState {
    if (failed) {
      return PreparedItemState.FAILED;
    }
    if (duplicate) {
      return PreparedItemState.DUPLICATE;
    }
    return hasInput ? PreparedItemState.READY : PreparedItemState.FAILED;
  }
}
