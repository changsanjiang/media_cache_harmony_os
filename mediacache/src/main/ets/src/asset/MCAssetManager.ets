import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import MCURL from '../utils/MCURL';
import MCConfigs from '../utils/MCConfigs';
import { MCRetryPromise } from '../utils/MCRetryPromise';

namespace MCAssetManager {
  const mMap: Map<string, IMCAsset> = new Map();
  const mInitPromises: Map<string, Promise<IMCAsset>> = new Map();
  const mRootDir = MCConfigs.context.filesDir + '/mc_media_cache';
  let mPreparationPromise: Promise<void> | undefined = undefined;

  export function prepare(): Promise<void> {
    if ( !mPreparationPromise ) {
      mPreparationPromise = new MCRetryPromise(async (resolve, reject) => {
        try {
          if ( !(await fileIo.access(mRootDir, fileIo.AccessModeType.EXIST)) ) {
            await fileIo.mkdir(mRootDir);
            resolve();
            return;
          }

          const assetDirNames = await fileIo.listFile(mRootDir).then(fileNames => fileNames.filter(name => name.startsWith('mc_')));
          for (let dirName of assetDirNames) {
            const parts = dirName.split('_');
            if ( parts.length === 3 ) {
              const assetId = parts[1];
              if ( !mMap.get(assetId) ) {
                const assetType: MCAssetType = parseInt(parts[2]);
                const assetDir = `${mRootDir}/${dirName}`;
                let asset = (assetType === MCAssetType.FILE_BASED) ? new FILEAsset(assetId, assetDir) : new HLSAsset(assetId, assetDir);
                await asset.prepare();
                mMap.set(assetId, asset);
              }
            }
          }
          resolve();
        }
        catch (error) {
          reject(error);
        }
      });
    }
    return mPreparationPromise;
  }

  export async function getAsset(assetId: string): Promise<IMCAsset | undefined> {
    let asset = mMap.get(assetId);
    if ( !asset ) {
      if ( mInitPromises.has(assetId) ) {
        asset = await mInitPromises.get(assetId);
      }
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
}

export default MCAssetManager;