import abilityTest from './Ability.test';
import libraryReadAuthorizationTest from './LibraryReadAuthorization.test';
import riskRegressionTest from './RiskRegression.test';
import artworkWorkSessionTest from './ArtworkWorkSession.test';
import nativeMediaCompatibilityTest from './NativeMediaCompatibility.test';
import libraryDatabaseMigrationTest from './LibraryDatabaseMigration.test';
import artworkCacheCleanupTest from './ArtworkCacheCleanup.test';
import musicLibraryArtworkCandidateTest from './MusicLibraryArtworkCandidate.test';

export default function testsuite() {
  libraryReadAuthorizationTest();
  abilityTest();
  riskRegressionTest();
  artworkWorkSessionTest();
  nativeMediaCompatibilityTest();
  libraryDatabaseMigrationTest();
  artworkCacheCleanupTest();
  musicLibraryArtworkCandidateTest();
}
