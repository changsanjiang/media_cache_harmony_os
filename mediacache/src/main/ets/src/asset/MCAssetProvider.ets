import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import MCURL from '../utils/MCURL';
import MCConfigs from '../utils/MCConfigs';

namespace MCAssetProvider {
  const mMap: Map<string, IMCAsset> = new Map();
  const mInitPromises: Map<string, Promise<IMCAsset>> = new Map();
  const mRootDir = MCConfigs.context.filesDir + '/mc_media_cache';

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

  async function initializeAsset(assetId: string, assetType: MCAssetType): Promise<IMCAsset> {
    try {
      const rootDir = await getRootDir();
      const dir = `${rootDir}/${assetId}`;
      let asset = (assetType === MCAssetType.FILE_BASED) ? new FILEAsset(assetId, dir) : new HLSAsset(assetId, dir);
      await asset.prepare();
      mMap.set(assetId, asset);
      return asset;
    }
    finally {
      mInitPromises.delete(assetId);
    }
  }

  let mRootDirCreated = false;
  async function getRootDir(): Promise<string> {
    if ( !mRootDirCreated ) {
      if ( !(await fileIo.access(mRootDir, fileIo.AccessModeType.EXIST)) ) {
        await fileIo.mkdir(mRootDir);
      }
      mRootDirCreated = true;
    }
    return mRootDir;
  }
}

export default MCAssetProvider;