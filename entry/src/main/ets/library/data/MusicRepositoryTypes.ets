import { ParsedArtwork, ParsedMetadata } from '../model/LibraryModels';
import { ArtworkPalette } from '../artwork/ArtworkPaletteExtractor';

export interface PaletteRefreshAsset {
  id: number;
  artworkPath: string;
  paletteVersion: number;
}

export interface ArtworkPaletteUpdate {
  id: number;
  palette: ArtworkPalette;
  expectedVersion: number;
}

export enum LibraryMaintenanceKind {
  ARTWORK_COLORS = 0
}

export interface LibraryMaintenanceItem {
  kind: LibraryMaintenanceKind;
  count: number;
}

export interface LibraryMaintenanceStatus {
  items: Array<LibraryMaintenanceItem>;
  total: number;
}

export interface LibraryRemovalCommit {
  removedCount: number;
  persistedUris: Array<string>;
}

export interface LibraryRemovalRepository {
  commitClearLibrary(): Promise<LibraryRemovalCommit>;
  commitRemoveTracks(trackIds: Array<number>): Promise<LibraryRemovalCommit>;
}

export interface PersistedPlaybackQueueItem {
  position: number;
  trackId: number;
}

export interface PersistedPlaybackQueueSnapshot {
  items: Array<PersistedPlaybackQueueItem>;
  currentPosition: number;
}

export interface ArtworkImportInput {
  metadata: ParsedArtwork;
  sourceHash?: string;
  smallHash?: string;
  smallPath?: string;
  smallFormat?: string;
  smallWidth?: number;
  smallHeight?: number;
  smallByteSize?: number;
  largeHash?: string;
  largePath?: string;
  largeFormat?: string;
  largeWidth?: number;
  largeHeight?: number;
  largeByteSize?: number;
  palettePrimary?: string;
  paletteSecondary?: string;
  paletteAccent?: string;
  primary?: boolean;
}

export interface TrackImportInput {
  uri: string;
  displayName: string;
  fileSize: number;
  modifiedAt: number;
  quickFingerprint: string;
  fullFingerprint: string;
  authorizationPersisted: boolean;
  metadata: ParsedMetadata;
  artworks?: Array<ArtworkImportInput>;
}

export interface ImportTrackResult {
  imported: boolean;
  trackId: number;
  duplicateSource?: string;
}

export interface DuplicateCandidate {
  trackId: number;
  uri: string;
  fullFingerprint: string;
}

export interface ArtworkAssetLookup {
  assetId: number;
  smallHash: string;
  smallPath: string;
  smallFormat: string;
  smallWidth: number;
  smallHeight: number;
  smallByteSize: number;
  largeHash: string;
  largePath: string;
  largeFormat: string;
  largeWidth: number;
  largeHeight: number;
  largeByteSize: number;
  palettePrimary: string;
  paletteSecondary: string;
  paletteAccent: string;
  paletteVersion: number;
  sourceWidth: number;
  sourceHeight: number;
}

export interface ArtworkCleanupCandidate {
  assetId: number;
  smallPath: string;
  largePath: string;
  deleteSmall: boolean;
  deleteLarge: boolean;
}
