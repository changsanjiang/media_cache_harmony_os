import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType, MCAssetTypeValues } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import MCURL from '../utils/MCURL';
import MCConfigs from '../utils/MCConfigs';

namespace MCAssetManager {
  const mMap: Map<string, IMCAsset> = new Map();
  const mInitPromises: Map<string, Promise<IMCAsset | undefined>> = new Map();
  const mRootDir = MCConfigs.context.filesDir + '/mc_media_cache';

  export async function getAsset(assetId: string): Promise<IMCAsset | undefined> {
    let asset = mMap.get(assetId);
    if ( !asset ) {
      if (!mInitPromises.has(assetId)) {
        mInitPromises.set(assetId, initializeAsset(assetId));
      }
      asset = await mInitPromises.get(assetId);
    }
    return asset;
  }

  export async function getAssetBy(requestTarget: string): Promise<IMCAsset> {
    const targetInfo = MCURL.parse(requestTarget);
    const assetType = targetInfo.assetType;
    const assetId = targetInfo.assetId;

    let asset = mMap.get(assetId);
    if (!asset) {
      if (!mInitPromises.has(assetId)) {
        mInitPromises.set(assetId, initializeAsset(assetId, assetType));
      }
      asset = await mInitPromises.get(assetId);
    }
    return asset!;
  }

  async function initializeAsset(assetId: string, assetType?: MCAssetType): Promise<IMCAsset | undefined> {
    try {
      if ( assetType === undefined ) {
        for (let type of MCAssetTypeValues) {
          const assetDir = `${mRootDir}/${generateAssetDirName(assetId, type)}`;
          const exists = await fileIo.access(assetDir, fileIo.AccessModeType.EXIST);
          if ( exists ) {
            assetType = type;
            break;
          }
        }
      }

      if ( assetType !== undefined ) {
        const assetDir = `${mRootDir}/${generateAssetDirName(assetId, assetType)}`;
        const asset = (assetType === MCAssetType.FILE_BASED) ? new FILEAsset(assetId, assetDir) : new HLSAsset(assetId, assetDir);
        await asset.prepare();
        mMap.set(assetId, asset);
        return asset;
      }

      return undefined;
    }
    finally {
      mInitPromises.delete(assetId);
    }
  }

  function generateAssetDirName(assetId: string, assetType: MCAssetType): string {
    return `mc_${assetId}_${assetType}`;
  }
}

export default MCAssetManager;