export interface MediaImportCancellation {
  isCancelled(): boolean;
}

export interface MediaImportWorkQueue {
  cancel(): void;
  waitForIdle(): Promise<void>;
}
