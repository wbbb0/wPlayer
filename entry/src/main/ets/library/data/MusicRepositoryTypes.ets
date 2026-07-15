import { ParsedArtwork, ParsedMetadata } from '../model/LibraryModels';

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
}

export interface ArtworkCleanupCandidate {
  assetId: number;
  smallPath: string;
  largePath: string;
  deleteSmall: boolean;
  deleteLarge: boolean;
}
