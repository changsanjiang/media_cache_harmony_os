import { describe, it, expect } from '@ohos/hypium';
import { MCAssetCapabilityRegistry } from '../main/ets/src/asset/MCAssetCapabilityRegistry';
import { MCAssetType } from '../main/ets/src/defines/MCAssetType';

export default function mcAssetCapabilityRegistryTest() {
  describe('MCAssetCapabilityRegistry', () => {
    it('DASH supports prefetch but not export', 0, () => {
      const caps = MCAssetCapabilityRegistry.getCapabilities(MCAssetType.DASH);
      expect(caps.prefetch).assertTrue();
      expect(caps.export).assertFalse();
      expect(caps.remotePlay).assertTrue();
    });

    it('FILE supports full capability set', 0, () => {
      const caps = MCAssetCapabilityRegistry.getCapabilities(MCAssetType.FILE_BASED);
      expect(caps.prefetch).assertTrue();
      expect(caps.export).assertTrue();
      expect(caps.localDirPlay).assertTrue();
    });
  });
}