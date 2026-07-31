import abilityTest from './Ability.test';
import riskRegressionTest from './RiskRegression.test';
import artworkWorkSessionTest from './ArtworkWorkSession.test';
import nativeMediaCompatibilityTest from './NativeMediaCompatibility.test';

export default function testsuite() {
  abilityTest();
  riskRegressionTest();
  artworkWorkSessionTest();
  nativeMediaCompatibilityTest();
}
