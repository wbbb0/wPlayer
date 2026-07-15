import localUnitTest from './LocalUnit.test';
import riskRegressionTest from './RiskRegression.test';

export default function testsuite() {
  localUnitTest();
  riskRegressionTest();
}
