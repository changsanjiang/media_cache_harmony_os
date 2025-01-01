import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType, MCAssetTypeValues } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import MCURL from '../utils/MCURL';
import MCConfigs from '../utils/MCConfigs';
import MCArrayUtils from '../utils/MCArrayUtils';
import MCFileIOUtils from '../utils/MCFileIOUtils';

namespace MCAssetManager {
  export interface AssetDirNameInfo {
    readonly assetId: string;
    readonly assetType: MCAssetType;
  }
  const mAssets: Map<string, IMCAsset> = new Map();
  const mInitPromises: Map<string, Promise<IMCAsset>> = new Map();
  const mRemovePromises: Map<string, Promise<void>> = new Map();
  const mSizes: Map<string, number> = new Map();
  const mRootDir = MCConfigs.context.filesDir + '/mc_media_cache';

  export async function getAssetByRequestTarget(requestTarget: string): Promise<IMCAsset> {
    const targetInfo = MCURL.parse(requestTarget);
    const assetType = targetInfo.assetType;
    const assetId = targetInfo.assetId;
    if ( mRemovePromises.has(assetId) ) {
      await mRemovePromises.get(assetId);
    }

    let asset = mAssets.get(assetId);
    if (!asset) {
      let promise = mInitPromises.get(assetId);
      if ( promise === undefined ) {
        promise = initializeAsset(assetId, assetType);
        mInitPromises.set(assetId, promise);
        try {
          asset = await promise;
        }
        finally {
          mInitPromises.delete(assetId);
        }
      }
      else {
        asset = await promise;
      }
    }
    return asset;
  }

  export async function removeAssetBy(assetId: string): Promise<void> {
    if ( mInitPromises.has(assetId) ) {
      await mInitPromises.get(assetId);
    }

    let promise = mRemovePromises.get(assetId);
    if ( promise === undefined ) {
      promise = removeAsset(assetId);
      mRemovePromises.set(assetId, promise);
      try {
        await promise;
      }
      finally {
        mRemovePromises.delete(assetId);
      }
    }
    else {
      await promise;
    }
  }

  /** 查询根目录下所有资产的id; */
  export async function queryAllAssetIds(): Promise<string[]> {
    const fileNames = await fileIo.listFile(mRootDir);
    const assetIds = MCArrayUtils.mapNotUndefined(fileNames, name => name.startsWith("mc_") ? parse(name).assetId : undefined);
    return assetIds;
  }

  /** 计算资产的缓存大小; */
  export async function calculateCacheSize(assetId: string): Promise<number> {
    if ( mRemovePromises.has(assetId) ) {
      await mRemovePromises.get(assetId);
    }

    // 如果内存中已引用资产, 则通过资产获取缓存大小;
    let asset = mAssets.get(assetId);
    if ( !asset && mInitPromises.has(assetId) ) {
      asset = await mInitPromises.get(assetId);
    }

    if ( asset ) {
      return asset.currentCachedSize;
    }

    // 否则通过路径查询文件大小;
    let size = mSizes.get(assetId);
    if ( size === undefined ) {
      try {
        const assetDir = await queryAssetDirBy(assetId);
        size = assetDir ? await MCFileIOUtils.calculateTotalBytes(assetDir) : 0;
      }
      catch (ignored) {
        size = 0;
      }
      mSizes.set(assetId, size);
    }
    return size;
  }

  export async function calculateCacheSizeForAssets(assetIds: string[]): Promise<number> {
    const concurrentCalculateCount = 3;
    let totalSize = 0;
    let idIndex = 0;
    while (idIndex < assetIds.length) {
      const promises: Promise<number>[] = [];
      for (let p = 0; p < concurrentCalculateCount; p++) {
        const assetId = assetIds[idIndex];
        const promise = calculateCacheSize(assetId);
        promises.push(promise);
        idIndex += 1;
        if ( idIndex >= assetIds.length ) break;
      }
      const values = await Promise.all(promises);
      totalSize = values.reduce((prev, size) => prev + size, totalSize);
    }
    return totalSize;
  }

  async function initializeAsset(assetId: string, assetType: MCAssetType): Promise<IMCAsset> {
    const assetDir = `${mRootDir}/${generateAssetDirName(assetId, assetType)}`;
    const asset = (assetType === MCAssetType.FILE_BASED) ? new FILEAsset(assetId, assetDir) : new HLSAsset(assetId, assetDir);
    await asset.prepare();
    mAssets.set(assetId, asset);
    mSizes.delete(assetId);
    return asset;
  }

  async function removeAsset(assetId: string): Promise<void> {
    let asset = mAssets.get(assetId);
    let assetDir: string | undefined = undefined;
    if ( asset ) {
      await asset.abort(new Error(`Asset will be removed!`));
      assetDir = `${mRootDir}/${generateAssetDirName(assetId, asset.type)}`;
    }
    else {
      assetDir = await queryAssetDirBy(assetId);
    }

    if ( assetDir ) {
      await MCFileIOUtils.deleteAllFiles(assetDir);
    }

    mAssets.delete(assetId);
    mSizes.delete(assetId);
  }

  /** 查询资产目录; */
  async function queryAssetDirBy(assetId: string): Promise<string | undefined> {
    for (let assetType of MCAssetTypeValues) {
      const assetDir = `${mRootDir}/${generateAssetDirName(assetId, assetType)}`;
      const exists = await fileIo.access(assetDir, fileIo.AccessModeType.EXIST);
      if ( exists ) {
        return assetDir;
      }
    }
    return undefined;
  }

  function generateAssetDirName(assetId: string, assetType: MCAssetType): string {
    return `mc_${assetId}_${assetType}`;
  }

  function parse(dirName: string): AssetDirNameInfo {
    const parts = dirName.split("_");
    const assetId = parts[1];
    const assetType = parseInt(parts[2]) as MCAssetType;
    const info: AssetDirNameInfo = {
      assetId: assetId,
      assetType: assetType
    };
    return info;
  }
}

export default MCAssetManager;