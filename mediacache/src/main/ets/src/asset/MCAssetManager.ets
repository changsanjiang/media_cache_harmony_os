import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType, MCAssetTypeValues } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import MCURL from '../utils/MCURL';
import MCConfigs from '../utils/MCConfigs';
import MCAssetUtils from './MCAssetUtils';
import MCUtils from '../utils/MCUtils';

namespace MCAssetManager {
  export interface AssetDirNameInfo {
    readonly assetId: string;
    readonly assetType: MCAssetType;
  }

  const mMap: Map<string, IMCAsset> = new Map();
  const mInitPromises: Map<string, Promise<IMCAsset | undefined>> = new Map();
  const mRootDir = MCConfigs.context.filesDir + '/mc_media_cache';
  let mRootDirCreated = false;
  let mRootDirPromise: Promise<void> | undefined = undefined;

  /** 从本地目录中查询 asset; */
  export async function queryAssets(predicate: (info: AssetDirNameInfo) => boolean): Promise<IMCAsset[]> {
    if ( !mRootDirCreated ) {
      await mkRootDirIfNotExists();
    }

    const fileNames = await fileIo.listFile(mRootDir);
    const assets = MCUtils.arrayMapNotUndefined(fileNames, name => {
     if ( name.startsWith("mc_") ) {
       const info = parse(name);
       if ( predicate(info) ) {
         return getAsset(info.assetId, info.assetType);
       }
     }
     return undefined;
    })
    return assets.length > 0 ? (await Promise.all(assets)) as IMCAsset[] : [];
  }

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

  async function getAsset(assetId: string, assetType?: MCAssetType): Promise<IMCAsset | undefined> {
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