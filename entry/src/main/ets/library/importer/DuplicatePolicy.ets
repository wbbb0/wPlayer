export class DuplicatePolicy {
  static isConfirmedDuplicate(existingQuick: string, candidateQuick: string,
    existingFull: string, candidateFull: string): boolean {
    return existingFull.length > 0 && existingFull === candidateFull;
  }
}
