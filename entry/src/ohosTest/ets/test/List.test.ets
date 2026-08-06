import abilityTest from './Ability.test';
import riskRegressionTest from './RiskRegression.test';
import artworkWorkSessionTest from './ArtworkWorkSession.test';
import nativeMediaCompatibilityTest from './NativeMediaCompatibility.test';
import libraryDatabaseMigrationTest from './LibraryDatabaseMigration.test';
import artworkCacheCleanupTest from './ArtworkCacheCleanup.test';

export default function testsuite() {
  abilityTest();
  riskRegressionTest();
  artworkWorkSessionTest();
  nativeMediaCompatibilityTest();
  libraryDatabaseMigrationTest();
  artworkCacheCleanupTest();
}
