import localUnitTest from './LocalUnit.test';
import riskRegressionTest from './RiskRegression.test';
import libraryPagingTest from './LibraryPaging.test';
import appRuntimeLifecycleTest from './AppRuntimeLifecycle.test';
import playbackQueueRegressionTest from './PlaybackQueueRegression.test';
import artworkCleanupRegressionTest from './ArtworkCleanupRegression.test';
import playbackPowerPolicyTest from './PlaybackPowerPolicy.test';
import libraryNavigationTest from './LibraryNavigation.test';
import albumGridLayoutTest from './AlbumGridLayout.test';
import m3uCodecTest from './M3uCodec.test';
import m3uImportMatcherTest from './M3uImportMatcher.test';
import playbackCoverageTest from './PlaybackCoverage.test';
import playlistInteractionPolicyTest from './PlaylistInteractionPolicy.test';
import playlistPolicyTest from './PlaylistPolicy.test';
import playbackStateReducerTest from './PlaybackStateReducer.test';

export default function testsuite() {
  localUnitTest();
  riskRegressionTest();
  libraryPagingTest();
  appRuntimeLifecycleTest();
  playbackQueueRegressionTest();
  artworkCleanupRegressionTest();
  playbackPowerPolicyTest();
  libraryNavigationTest();
  albumGridLayoutTest();
  m3uCodecTest();
  m3uImportMatcherTest();
  playbackCoverageTest();
  playlistInteractionPolicyTest();
  playlistPolicyTest();
  playbackStateReducerTest();
}
