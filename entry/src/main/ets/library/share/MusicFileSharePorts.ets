import { common } from '@kit.AbilityKit';

export enum MusicFileShareDataKind {
  AUDIO = 0
}

export interface MusicFileSharePayload {
  kind: MusicFileShareDataKind;
  uri: string;
  title: string;
  description: string;
}

export interface MusicFileShareTrack {
  uri: string;
  title: string;
  displayName: string;
  artistDisplay: string;
}

export interface TrackShareSource {
  getShareTrack(trackId: number): Promise<MusicFileShareTrack | undefined>;
}

export interface PickerUriAccessActivator {
  activate(uri: string): Promise<boolean>;
}

export interface MusicFileSharePresenter {
  show(context: common.UIAbilityContext, payload: MusicFileSharePayload): Promise<void>;
}

export enum MusicFileShareErrorKind {
  TRACK_LOOKUP_FAILED = 0,
  TRACK_NOT_FOUND = 1,
  URI_MISSING = 2,
  AUTHORIZATION_FAILED = 3,
  SHARE_PANEL_FAILED = 4
}

export class MusicFileShareError extends Error {
  readonly kind: MusicFileShareErrorKind;

  constructor(kind: MusicFileShareErrorKind, message: string) {
    super(message);
    this.kind = kind;
  }
}
