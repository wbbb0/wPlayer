import { describe, expect, it } from '@ohos/hypium';
import { TabReselectionPolicy } from
  '../main/ets/components/navigation/TabReselectionPolicy';
import { IndexNavigationController } from
  '../main/ets/components/navigation/IndexNavigationController';
import {
  NavigationRoute,
  navigationItemIndex
} from '../main/ets/components/navigation/MoreNavigation';

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
  });
}
