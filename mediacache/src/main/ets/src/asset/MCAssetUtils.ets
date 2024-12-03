import { url } from '@kit.ArkTS';
import { MCUtils } from '../../../../../Index';
import { MCAssetType } from '../defines/MCAssetType';
import MCConfigs from '../utils/MCConfigs';

namespace MCAssetUtils {
  export async function resolveAssetType(resUrl: string): Promise<MCAssetType> {
    if ( MCConfigs.resolveAssetType ) {
      return MCConfigs.resolveAssetType(resUrl);
    }

    const pathname = url.URL.parseURL(resUrl).pathname;
    if ( pathname.endsWith('.m3u8') || pathname.endsWith('.m3u') ) {
      return MCAssetType.HLS;
    }
    return MCAssetType.FILE_BASED;
  }

  export async function generateAssetId(assetUrl: string): Promise<string> {
    const target = MCConfigs.resolveAssetIdentifier ? (await MCConfigs.resolveAssetIdentifier(assetUrl)) : assetUrl;
    return MCUtils.hash(target);
  }
}

export default MCAssetUtils;