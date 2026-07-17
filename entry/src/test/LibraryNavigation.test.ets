import { describe, expect, it } from '@ohos/hypium';
import {
  LibraryEntityKind,
  TrackNavigationTargets
} from '../main/ets/library/model/LibraryModels';
import {
  LibraryLinkRole,
  libraryLinkActions
} from '../main/ets/components/navigation/LibraryNavigation';

function targets(): TrackNavigationTargets {
  return {
    trackId: 1,
    trackArtists: [
      { id: 10, name: 'Artist A' },
      { id: 11, name: 'Artist B' }
    ],
    albumArtists: [
      { id: 10, name: 'Artist A' },
      { id: 12, name: 'Artist C' }
    ],
    album: {
      id: 20,
      title: 'Album X',
      palettePrimary: '#FF000000'
    }
  };
}

export default function libraryNavigationTest() {
  describe('Library navigation policy', () => {
    it('deduplicates people shared by track and album credits', 0, () => {
      const actions = libraryLinkActions(targets());
      expect(actions.length).assertEqual(4);
      expect(actions[0].target.identity.id).assertEqual(10);
      expect(actions[1].target.identity.id).assertEqual(11);
      expect(actions[2].target.identity.id).assertEqual(12);
      expect(actions[3].role).assertEqual(LibraryLinkRole.ALBUM);
    });

    it('hides only the current artist and keeps recursive alternatives', 0, () => {
      const actions = libraryLinkActions(targets(), {
        kind: LibraryEntityKind.ARTIST,
        id: 10
      });
      expect(actions.length).assertEqual(3);
      expect(actions[0].target.identity.id).assertEqual(11);
      expect(actions[1].target.identity.id).assertEqual(12);
      expect(actions[2].target.identity.id).assertEqual(20);
    });

    it('hides the current album without hiding its artists', 0, () => {
      const actions = libraryLinkActions(targets(), {
        kind: LibraryEntityKind.ALBUM,
        id: 20
      });
      expect(actions.length).assertEqual(3);
      expect(actions[0].target.identity.kind).assertEqual(LibraryEntityKind.ARTIST);
      expect(actions[2].target.identity.id).assertEqual(12);
    });
  });
}
