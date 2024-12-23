import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType, MCAssetTypeValues } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import MCURL from '../utils/MCURL';
import MCConfigs from '../utils/MCConfigs';
import MCAssetUtils from './MCAssetUtils';
import MCArrayUtils from '../utils/MCArrayUtils';
import MCFileIOUtils from '../utils/MCFileIOUtils';

namespace MCAssetManager {
  export interface AssetDirNameInfo {
    readonly assetId: string;
    readonly assetType: MCAssetType;
  }
  const mAssets: Map<string, IMCAsset> = new Map();
  const mInitPromises: Map<string, Promise<IMCAsset | undefined>> = new Map();
  const mSizes: Map<string, number> = new Map();
  const mRootDir = MCConfigs.context.filesDir + '/mc_media_cache';
  let mRootDirCreated = false;
  let mRootDirPromise: Promise<void> | undefined = undefined;

  export async function getAssetById(assetId: string): Promise<IMCAsset | undefined> {
    return getAsset(assetId, undefined);
  }

  export async function getAssetByRequestTarget(requestTarget: string): Promise<IMCAsset> {
    const targetInfo = MCURL.parse(requestTarget);
    const assetType = targetInfo.assetType;
    const assetId = targetInfo.assetId;
    return getAsset(assetId, assetType) as Promise<IMCAsset>;
  }

  export async function getAssetByUrl(resUrl: string): Promise<IMCAsset> {
    const assetId = await MCAssetUtils.generateAssetId(resUrl);
    const assetType = await MCAssetUtils.resolveAssetType(resUrl);
    return getAsset(assetId, assetType) as Promise<IMCAsset>;
  }

  export async function removeAssetBy(assetId: string): Promise<void> {
    // TODO() 删除资产
  }

  /** 查询根目录下所有资产的id; */
  export async function queryAllAssetIds(): Promise<string[]> {
    const fileNames = await fileIo.listFile(mRootDir);
    const assetIds = MCArrayUtils.mapNotUndefined(fileNames, name => name.startsWith("mc_") ? parse(name).assetId : undefined);
    return assetIds;
  }

  /** 计算资产的缓存大小; */
  export async function calculateCacheSize(assetId: string): Promise<number> {
    // 如果内存中已引用资产, 则通过资产获取缓存大小;
    let asset = mAssets.get(assetId);
    if ( !asset && mInitPromises.has(assetId) ) {
      asset = await mInitPromises.get(assetId);
    }

    if ( asset ) {
      return asset.cacheSize;
    }

    // 否则通过路径查询文件大小;
    let size = mSizes.get(assetId);
    if ( size === undefined ) {
      try {
        for (let type of MCAssetTypeValues) {
          const assetDir = `${mRootDir}/${generateAssetDirName(assetId, type)}`;
          const exists = await fileIo.access(assetDir, fileIo.AccessModeType.EXIST);
          if ( exists ) {
            size = await MCFileIOUtils.calculateTotalBytes(assetDir);
            break;
          }
        }
      } catch (ignored) { }
      if ( size === undefined ) size = 0;
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

  async function getAsset(assetId: string, assetType?: MCAssetType): Promise<IMCAsset | undefined> {
    let asset = mAssets.get(assetId);
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
      if ( !mRootDirCreated ) {
        await mkRootDirIfNotExists();
      }

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
        mAssets.set(assetId, asset);
        mSizes.delete(assetId);
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

  async function mkRootDirIfNotExists(): Promise<void> {
    if ( !mRootDirCreated ) {
      if ( !mRootDirPromise ) {
        mRootDirPromise = new Promise(async (resolve, reject) => {
          try {
            const exists = await fileIo.access(mRootDir, fileIo.AccessModeType.EXIST);
            if ( !exists ) {
              await fileIo.mkdir(mRootDir, true);
            }
            mRootDirCreated = true;
            resolve();
          }
          catch (error) {
            reject(error);
          }
          finally {
            mRootDirPromise = undefined;
          }
        });
      }
      await mRootDirPromise;
    }
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