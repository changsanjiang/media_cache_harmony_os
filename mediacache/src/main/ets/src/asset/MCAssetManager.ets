import { MCURL } from '../../../../../Index';
import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';

namespace MCAssetManager {
  const mMap: Map<string, IMCAsset> = new Map();

  // asset readwrite retained, should release after;
  export async function getAssetBy(requestTarget: string): Promise<IMCAsset> {
    const targetInfo = MCURL.parse(requestTarget);
    const assetId = targetInfo.assetId;
    let asset = mMap.get(assetId);
    if ( !asset ) {
      const rootDir = await getRootDirUnsafe();
      const dir = `${rootDir}/${assetId}`;
      asset = targetInfo.assetType === MCAssetType.FILE_BASED ? new FILEAsset(assetId, dir) : new HLSAsset(assetId, dir);
      await asset.prepare();
      mMap.set(assetId, asset);
    }
    return asset.readwriteRetain();
  }

  const mRootDir = getContext(mMap).filesDir + '/mc_media_cache';
  let mRootDirExists = false;
  async function getRootDirUnsafe(): Promise<string> {
    if ( !mRootDirExists ) {
      if ( !(await fileIo.access(mRootDir, fileIo.AccessModeType.EXIST)) ) {
        await fileIo.mkdir(mRootDir);
      }
      mRootDirExists = true;
    }
    return mRootDir;
  }
}

export default MCAssetManager;