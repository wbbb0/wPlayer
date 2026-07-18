import { fileIo } from '@kit.CoreFileKit';

export class FileIoSafety {
  static operationError(operation: string, error: Object): Error {
    const message = error instanceof Error ? error.message : `${error}`;
    return new Error(`${operation}: ${message}`);
  }

  static async close(file: fileIo.File | undefined, operation: string): Promise<void> {
    if (file === undefined) {
      return;
    }
    try {
      await fileIo.close(file);
    } catch (error) {
      console.warn(`Unable to close ${operation}: ${error instanceof Error ? error.message : `${error}`}`);
    }
  }
}
