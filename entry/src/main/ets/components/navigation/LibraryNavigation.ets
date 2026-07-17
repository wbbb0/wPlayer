import {
  AlbumReference,
  ArtistReference,
  LibraryEntityIdentity,
  LibraryEntityKind,
  LibraryNavigationTarget,
  TrackNavigationTargets
} from '../../library/model/LibraryModels';
import {
  AlbumDetailState,
  ArtistDetailState
} from '../../library/store/LibraryDetailState';

let routeInstanceId: number = 0;

export class LibraryDetailRoute {
  static readonly ALBUM: string = 'libraryAlbumDetail';
  static readonly ARTIST: string = 'libraryArtistDetail';
}

export class AlbumDetailRouteParams {
  readonly instanceId: number;
  readonly albumId: number;
  readonly title: string;
  readonly palettePrimary: string;
  readonly state: AlbumDetailState;
  readonly scroller: Scroller = new Scroller();

  constructor(albumId: number, title: string, palettePrimary: string) {
    this.instanceId = ++routeInstanceId;
    this.albumId = albumId;
    this.title = title;
    this.palettePrimary = palettePrimary;
    this.state = new AlbumDetailState(albumId);
  }

  identity(): LibraryEntityIdentity {
    return albumIdentity(this.albumId);
  }

  anchorPrefix(): string {
    return `album_${this.instanceId}`;
  }
}

export class ArtistDetailRouteParams {
  readonly instanceId: number;
  readonly artistId: number;
  readonly name: string;
  readonly state: ArtistDetailState;
  readonly scroller: Scroller = new Scroller();

  constructor(artistId: number, name: string) {
    this.instanceId = ++routeInstanceId;
    this.artistId = artistId;
    this.name = name;
    this.state = new ArtistDetailState(artistId);
  }

  identity(): LibraryEntityIdentity {
    return artistIdentity(this.artistId);
  }

  anchorPrefix(): string {
    return `artist_${this.instanceId}`;
  }
}

export enum LibraryLinkRole {
  TRACK_ARTIST = 0,
  ALBUM_ARTIST = 1,
  ALBUM = 2
}

export interface LibraryLinkAction {
  role: LibraryLinkRole;
  label: string;
  target: LibraryNavigationTarget;
}

export function artistIdentity(id: number): LibraryEntityIdentity {
  return { kind: LibraryEntityKind.ARTIST, id: id };
}

export function albumIdentity(id: number): LibraryEntityIdentity {
  return { kind: LibraryEntityKind.ALBUM, id: id };
}

export function artistTarget(artist: ArtistReference): LibraryNavigationTarget {
  return {
    identity: artistIdentity(artist.id),
    title: artist.name,
    palettePrimary: ''
  };
}

export function albumTarget(album: AlbumReference): LibraryNavigationTarget {
  return {
    identity: albumIdentity(album.id),
    title: album.title,
    palettePrimary: album.palettePrimary
  };
}

export function sameLibraryEntity(
  left: LibraryEntityIdentity | undefined,
  right: LibraryEntityIdentity
): boolean {
  return left !== undefined && left.kind === right.kind && left.id === right.id;
}

function hasTarget(actions: Array<LibraryLinkAction>, target: LibraryNavigationTarget): boolean {
  for (let index = 0; index < actions.length; index += 1) {
    if (sameLibraryEntity(actions[index].target.identity, target.identity)) {
      return true;
    }
  }
  return false;
}

function appendArtistActions(
  actions: Array<LibraryLinkAction>,
  artists: Array<ArtistReference>,
  role: LibraryLinkRole,
  current: LibraryEntityIdentity | undefined
): void {
  for (let index = 0; index < artists.length; index += 1) {
    const target = artistTarget(artists[index]);
    if (!sameLibraryEntity(current, target.identity) && !hasTarget(actions, target)) {
      actions.push({
        role: role,
        label: artists[index].name,
        target: target
      });
    }
  }
}

export function libraryLinkActions(
  targets: TrackNavigationTargets,
  current?: LibraryEntityIdentity
): Array<LibraryLinkAction> {
  const actions: Array<LibraryLinkAction> = [];
  appendArtistActions(actions, targets.trackArtists, LibraryLinkRole.TRACK_ARTIST, current);
  appendArtistActions(actions, targets.albumArtists, LibraryLinkRole.ALBUM_ARTIST, current);
  if (targets.album !== undefined) {
    const target = albumTarget(targets.album);
    if (!sameLibraryEntity(current, target.identity)) {
      actions.push({
        role: LibraryLinkRole.ALBUM,
        label: targets.album.title,
        target: target
      });
    }
  }
  return actions;
}

export function libraryLinkRoleLabel(role: LibraryLinkRole): string {
  if (role === LibraryLinkRole.TRACK_ARTIST) {
    return '艺术家';
  }
  if (role === LibraryLinkRole.ALBUM_ARTIST) {
    return '专辑艺术家';
  }
  return '专辑';
}
