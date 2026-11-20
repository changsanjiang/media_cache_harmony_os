import localUnitTest from './LocalUnit.test';
import nodeListUnitTest from './NodeListUnit.test';
import mcAssetCapabilityRegistryTest from './MCAssetCapabilityRegistry.test';
import mcHttpReceiveBufferTest from './MCHttpReceiveBuffer.test';
import mcHttpWireFormatTest from './MCHttpWireFormat.test';

export default function testsuite() {
  localUnitTest();
  nodeListUnitTest();
  mcAssetCapabilityRegistryTest();
  mcHttpReceiveBufferTest();
  mcHttpWireFormatTest();
}