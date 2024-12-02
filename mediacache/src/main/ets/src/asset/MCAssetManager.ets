import { IMCAsset } from '../defines/IMCAsset';

namespace MCAssetManager {
  export function getAssetBy(requestTarget: string): Promise<IMCAsset> {
    throw new Error("Method not implemented.");
  }
}

export default MCAssetManager;