import localUnitTest from './LocalUnit.test';
import nodeListUnitTest from './NodeListUnit.test';

export default function testsuite() {
  localUnitTest();
  nodeListUnitTest();
}