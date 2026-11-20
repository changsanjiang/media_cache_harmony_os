import localUnitTest from './LocalUnit.test';
import nodeListUnitTest from './NodeListUnit.test';
import mcAssetCapabilityRegistryTest from './MCAssetCapabilityRegistry.test';

export default function testsuite() {
  localUnitTest();
  nodeListUnitTest();
  mcAssetCapabilityRegistryTest();
}