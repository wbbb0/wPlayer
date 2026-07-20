import abilityTest from './Ability.test';
import riskRegressionTest from './RiskRegression.test';
import artworkWorkSessionTest from './ArtworkWorkSession.test';

export default function testsuite() {
  abilityTest();
  riskRegressionTest();
  artworkWorkSessionTest();
}
