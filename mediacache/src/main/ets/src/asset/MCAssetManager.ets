import { MCURL } from '../../../../../Index';
import { IMCAsset } from '../defines/IMCAsset';

namespace MCAssetManager {
  export function getAssetBy(requestTarget: string): Promise<IMCAsset> {
    const targetInfo = MCURL.parse(requestTarget);

    throw new Error("Method not implemented.");
  }
}

export default MCAssetManager;