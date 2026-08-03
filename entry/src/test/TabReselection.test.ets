import { describe, expect, it } from '@ohos/hypium';
import { TabReselectionPolicy } from
  '../main/ets/components/navigation/TabReselectionPolicy';
import { IndexNavigationController } from
  '../main/ets/components/navigation/IndexNavigationController';
import {
  NavigationRoute,
  navigationItemIndex,
  normalizeNavigationOrder
} from '../main/ets/components/navigation/MoreNavigation';
import { LibraryDetailRoute } from '../main/ets/components/navigation/LibraryNavigation';

export default function tabReselectionTest() {
  describe('Tab reselection policy', () => {
    it('recognizes a click on the selected tab', 0, () => {
      expect(TabReselectionPolicy.isReselection(0, 0)).assertTrue();
      expect(TabReselectionPolicy.isReselection(4, 4)).assertTrue();
    });

    it('ignores the click that starts a tab switch', 0, () => {
      expect(TabReselectionPolicy.isReselection(1, 0)).assertFalse();
    });

    it('recognizes the first click after a completed switch', 0, () => {
      expect(TabReselectionPolicy.isReselection(1, 0)).assertFalse();
      expect(TabReselectionPolicy.isReselection(1, 1)).assertTrue();
    });

    it('uses each tab host current index independently', 0, () => {
      expect(TabReselectionPolicy.isReselection(4, 4)).assertTrue();
      expect(TabReselectionPolicy.isReselection(6, 6)).assertTrue();
      expect(TabReselectionPolicy.isReselection(6, 4)).assertFalse();
    });

    it('keeps the old root stack on switch and clears only the reselected root', 0, () => {
      const controller = new IndexNavigationController();
      const playlistsStack = controller.rootPathStacks[
        navigationItemIndex(NavigationRoute.PLAYLISTS)
      ];
      playlistsStack.pushPath({ name: 'playlist-detail' }, false);

      controller.handleCompactTabBarClick(1);
      expect(playlistsStack.getAllPathName().length).assertEqual(1);

      controller.handleCompactTabChange(1);
      const songsStack = controller.rootPathStacks[
        navigationItemIndex(NavigationRoute.SONGS)
      ];
      songsStack.pushPath({ name: 'artist-detail' }, false);
      controller.handleCompactTabBarClick(1);

      expect(songsStack.getAllPathName().length).assertEqual(0);
      expect(playlistsStack.getAllPathName().length).assertEqual(1);
    });

    it('clears the compact More stack and expanded root stack independently', 0, () => {
      const controller = new IndexNavigationController();
      controller.selectRoute(NavigationRoute.SETTINGS);
      controller.morePathStack.pushPath({ name: NavigationRoute.SETTINGS }, false);
      const settingsRootStack = controller.rootPathStacks[
        navigationItemIndex(NavigationRoute.SETTINGS)
      ];
      settingsRootStack.pushPath({ name: 'settings-detail' }, false);

      controller.handleCompactTabBarClick(controller.compactTabIndex());
      expect(controller.morePathStack.getAllPathName().length).assertEqual(0);
      expect(settingsRootStack.getAllPathName().length).assertEqual(1);

      controller.handleExpandedTabBarClick(controller.expandedTabIndex());
      expect(settingsRootStack.getAllPathName().length).assertEqual(0);
    });

    it('appends new artist and genre roots to an older saved order', 0, () => {
      const normalized = normalizeNavigationOrder([
        NavigationRoute.PLAYLISTS,
        NavigationRoute.SONGS,
        NavigationRoute.ALBUMS,
        NavigationRoute.LIBRARY_MANAGEMENT
      ]);
      expect(normalized.includes(NavigationRoute.ARTISTS)).assertTrue();
      expect(normalized.includes(NavigationRoute.GENRES)).assertTrue();
      expect(normalized.indexOf(NavigationRoute.ARTISTS) > normalized.indexOf(NavigationRoute.ALBUMS)).assertTrue();
      expect(normalized.indexOf(NavigationRoute.GENRES) > normalized.indexOf(NavigationRoute.ARTISTS)).assertTrue();
    });

    it('opens a genre collection on the active compact More stack', 0, () => {
      const controller = new IndexNavigationController();
      controller.selectRoute(NavigationRoute.GENRES);
      controller.openGenreTracks(7, '摇滚', false);
      const names = controller.morePathStack.getAllPathName();
      expect(names.length).assertEqual(1);
      expect(names[0]).assertEqual(LibraryDetailRoute.GENRE_TRACKS);
    });
  });
}
