import { relationalStore } from '@kit.ArkData';

export class RelationalStoreSafety {
  static operationError(operation: string, error: Object): Error {
    return new Error(`${operation}: ${RelationalStoreSafety.errorMessage(error)}`);
  }

  static closeResultSet(resultSet: relationalStore.ResultSet | undefined, operation: string): void {
    if (resultSet === undefined) {
      return;
    }
    try {
      resultSet.close();
    } catch (error) {
      console.warn(`Unable to close ${operation} result set: ${RelationalStoreSafety.errorMessage(error)}`);
    }
  }

  static errorMessage(error: Object): string {
    return error instanceof Error ? error.message : `${error}`;
  }
}
