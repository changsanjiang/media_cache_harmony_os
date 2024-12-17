import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType, MCAssetTypeValues } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import MCURL from '../utils/MCURL';
import MCConfigs from '../utils/MCConfigs';

namespace MCAssetManager {
  const mMap: Map<string, IMCAsset> = new Map();
  const mInitPromises: Map<string, Promise<IMCAsset>> = new Map();
  const mFindPromises: Map<string, Promise<IMCAsset | undefined>> = new Map();
  const mRootDir = MCConfigs.context.filesDir + '/mc_media_cache';

  export async function getAsset(assetId: string): Promise<IMCAsset | undefined> {
    let asset = mMap.get(assetId);
    if ( !asset ) {
      if ( mInitPromises.has(assetId) ) {
        asset = await mInitPromises.get(assetId);
      }

      if ( !mFindPromises.has(assetId) ) {
        mFindPromises.set(assetId, findAsset(assetId));
      }

      asset = await mFindPromises.get(assetId);
    }
    return asset;
  }

  export async function getAssetBy(requestTarget: string): Promise<IMCAsset> {
    const targetInfo = MCURL.parse(requestTarget);
    const assetType = targetInfo.assetType;
    const assetId = targetInfo.assetId;
    let asset = mMap.get(assetId);

    if (!asset) {
      if ( mFindPromises.has(assetId) ) {
        asset = await mFindPromises.get(assetId);
      }

      if ( !asset ) {
        if (!mInitPromises.has(assetId)) {
          mInitPromises.set(assetId, initializeAsset(assetId, assetType));
        }
        asset = await mInitPromises.get(assetId);
      }
    }
    return asset!;
  }

  async function initializeAsset(assetId: string, assetType: MCAssetType): Promise<IMCAsset> {
    try {
      const assetDir = `${mRootDir}/mc_${assetId}_${assetType}`;
      let asset = (assetType === MCAssetType.FILE_BASED) ? new FILEAsset(assetId, assetDir) : new HLSAsset(assetId, assetDir);
      await asset.prepare();
      mMap.set(assetId, asset);
      return asset;
    }
    finally {
      mInitPromises.delete(assetId);
    }
  }

  /** 从本地目录中查找 asset; */
  async function findAsset(assetId: string): Promise<IMCAsset | undefined> {
    try {
      for (let assetType of MCAssetTypeValues) {
        const assetDir = `${mRootDir}/mc_${assetId}_${assetType}`;
        const exists = await fileIo.access(assetDir, fileIo.AccessModeType.EXIST);
        if ( exists ) {
          const asset = await initializeAsset(assetId, assetType);
          return asset;
        }
      }
      return undefined;
    }
    finally {
       mFindPromises.delete(assetId);
    }
  }
}

export default MCAssetManager;