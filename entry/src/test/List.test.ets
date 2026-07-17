import localUnitTest from './LocalUnit.test';
import riskRegressionTest from './RiskRegression.test';
import libraryPagingTest from './LibraryPaging.test';
import appRuntimeLifecycleTest from './AppRuntimeLifecycle.test';
import playbackQueueRegressionTest from './PlaybackQueueRegression.test';
import artworkCleanupRegressionTest from './ArtworkCleanupRegression.test';
import playbackPowerPolicyTest from './PlaybackPowerPolicy.test';

export default function testsuite() {
  localUnitTest();
  riskRegressionTest();
  libraryPagingTest();
  appRuntimeLifecycleTest();
  playbackQueueRegressionTest();
  artworkCleanupRegressionTest();
  playbackPowerPolicyTest();
}
