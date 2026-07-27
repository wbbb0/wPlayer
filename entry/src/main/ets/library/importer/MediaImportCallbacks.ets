import {
  FileCheckProgress,
  ImportItemResult,
  ImportProgress
} from '../model/LibraryModels';

export type ImportProgressCallback = (progress: ImportProgress) => void;
export type ImportStartedCallback = () => void;
export type ImportItemCallback = (item: ImportItemResult) => void;
export type FileCheckProgressCallback = (progress: FileCheckProgress) => void;

export enum ImportRefreshPhase {
  METADATA = 'metadata',
  ARTWORK = 'artwork'
}

export type ImportLibraryChangedCallback =
  (phase: ImportRefreshPhase) => Promise<void>;
