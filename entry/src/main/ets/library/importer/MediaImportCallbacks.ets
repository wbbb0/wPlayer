import {
  FileCheckProgress,
  ImportItemResult,
  ImportProgress
} from '../model/LibraryModels';
import { ImportUriTree } from './ImportUriTree';

export type ImportProgressCallback = (progress: ImportProgress) => void;
export type ImportStartedCallback = () => void;
export type ImportItemCallback = (item: ImportItemResult) => void;
export type FileCheckProgressCallback = (progress: FileCheckProgress) => void;

/**
 * Resolves the import range when the picked URIs span more than one
 * directory. Resolves with the URIs to import, or undefined to cancel the
 * import before any read permission is persisted.
 */
export type ImportTreeSelectionCallback =
  (tree: ImportUriTree) => Promise<Array<string> | undefined>;

export enum ImportRefreshPhase {
  METADATA = 'metadata',
  ARTWORK = 'artwork'
}

export type ImportLibraryChangedCallback =
  (phase: ImportRefreshPhase) => Promise<void>;
