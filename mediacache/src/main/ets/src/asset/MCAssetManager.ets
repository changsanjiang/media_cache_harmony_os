import { IMCAsset } from '../defines/IMCAsset';
import { MCAssetType, MCAssetTypeValues } from '../defines/MCAssetType';
import { FILEAsset } from './filebased/FILEAsset';
import { HLSAsset } from './hls/HLSAsset';
import { fileIo } from '@kit.CoreFileKit';
import { MCProxyUtils } from '../utils/MCProxyUtils';
import MCArrayUtils from '../utils/MCArrayUtils';
import MCFileIOUtils from '../utils/MCFileIOUtils';

export interface IMCAssetManager {
  /**
   * 初始化管理器, 进行必要的准备工作.
   */
  prepare(context: Context): Promise<void>;

  /**
   * 根据代理路径获取对应资产对象.
   */
  getAssetByProxyPath(proxyPath: string): Promise<IMCAsset>;

  /**
   * 移除指定 ID 的资产缓存.
   * @param assetId 资产唯一标识.
   */
  removeAssetBy(assetId: string): Promise<void>;

  /**
   * 获取所有缓存中的资产 ID 列表.
   */
  getAllAssetIds(): Promise<string[]>;  
  
  /**
   * 获取指定资产的本地缓存大小（单位：字节）.
   * @param assetId 资产唯一标识.
   */
  calculateCacheSize(assetId: string): Promise<number>;

  /**
   * 获取多个资产的本地缓存总大小（单位：字节）.
   * @param assetIds 资产 ID 数组.
   */
  calculateCacheSizeForAssets(assetIds: string[]): Promise<number>;
}

interface IMCAssetDirectoryManager {
  /**
   * 初始化管理器, 进行必要的准备工作.
   */
  prepare(context: Context): Promise<void>;

  /**
   * 根据 assetId、assetType 生成资产目录路径;
   * */
  resolveDirPath(assetId: string, assetType: MCAssetType): string;
  /**
   * 根据 assetId、assetType 生成资产目录名称(不含路径);
   * */
  resolveDirName(assetId: string, assetType: MCAssetType): string;

  /**
   * 查询根目录下指定资产的路径(如果根目录下存在该资产, 则返回资产路径, 否则返回 undefined)
   * */
  findDirPath(assetId: string): Promise<string | undefined>;

  /**
   * 获取所有缓存中的资产 ID 列表.
   */
  getAllAssetIds(): Promise<string[]>;

  /**
   * 获取指定资产的本地缓存大小（单位：字节）.
   * @param assetId 资产唯一标识.
   */
  calculateSize(assetId: string): Promise<number>;

  /**
   * 获取多个资产的本地缓存总大小（单位：字节）.
   * @param assetIds 资产 ID 数组.
   */
  calculateSizeForAssets(assetIds: string[]): Promise<Map<string, number>>;
}

interface MCAssetDirNameInfo {
  readonly assetId: string;
  readonly assetType: MCAssetType;
}

class MCAssetDirectoryManager implements IMCAssetDirectoryManager {
  // 资产根目录
  private mRootDirectoryPath: string = '';
  private mPrefix = "mc";

  async prepare(context: Context): Promise<void> {
    this.mRootDirectoryPath = context.filesDir + '/mc_media_cache';
  }

  resolveDirPath(assetId: string, assetType: MCAssetType): string {
    return `${this.mRootDirectoryPath}/${this.resolveDirName(assetId, assetType)}`;
  }

  resolveDirName(assetId: string, assetType: MCAssetType): string {
    // dir name format: prefix_assetId_assetType
    return `${this.mPrefix}_${assetId}_${assetType}`;
  }

  async findDirPath(assetId: string): Promise<string | undefined> {
    for ( let assetType of MCAssetTypeValues ) {
      const dirPath = this.resolveDirPath(assetId, assetType);
      try {
        const isExists = await fileIo.access(dirPath, fileIo.AccessModeType.EXIST);
        if ( isExists ) {
          return dirPath;
        }
      }
      catch (e) {}
    }
    return undefined;
  }

  async getAllAssetIds(): Promise<string[]> {
    const dirNames = await fileIo.listFile(this.mRootDirectoryPath);
    return MCArrayUtils.mapNotUndefined(dirNames, (name) => this.parseDirName(name)?.assetId);
  }

  async calculateSize(assetId: string): Promise<number> {
    const dirPath = await this.findDirPath(assetId);
    if ( dirPath ) {
      return await MCFileIOUtils.calculateTotalBytes(dirPath);
    }
    return 0;
  }

  async calculateSizeForAssets(assetIds: string[]): Promise<Map<string, number>> {
    const concurrentCalculateCount = 3;
    const map: Map<string, number> = new Map();
    let idIndex = 0;
    while (idIndex < assetIds.length) {
      const batch = assetIds.slice(idIndex, idIndex + concurrentCalculateCount);
      const sizes = await Promise.all(batch.map(async (id) => {
        const size = await this.calculateSize(id);
        return [id, size] as [string, number];
      }));
      for (let pair of sizes) {
        map.set(pair[0], pair[1]);
      }
      idIndex += concurrentCalculateCount;
    }
    return map;
  }

  private parseDirName(name: string): MCAssetDirNameInfo | undefined {
    // dir name format: prefix_assetId_assetType
    if ( !name.startsWith(this.mPrefix) ) {
      return undefined;
    }
    const parts = name.split("_");
    if ( parts.length != 3 ) {
      return undefined;
    }

    const assetId = parts[1];
    const assetType = Number(parts[2]);
    if (!MCAssetTypeValues.includes(assetType)) {
      return undefined;
    }

    return {
      assetId: assetId,
      assetType: assetType
    };
  }
}

export class MCAssetManager implements IMCAssetManager {
  private static shared: IMCAssetManager;

  static getInstance(): IMCAssetManager {
    if ( !MCAssetManager.shared ) {
      MCAssetManager.shared = new MCAssetManager();
    }
    return MCAssetManager.shared;
  }

  // 内存缓存: 缓存已获取的资产
  // key: assetId
  private mAssetMap: Map<string, IMCAsset> = new Map();
  // 内存缓存: 缓存已计算的资产占用的字节
  // key: assetId
  private mSizeMap: Map<string, number> = new Map();

  // 内存缓存: 缓存资产id列表
  // 调用 getAllAssetIds 时才进行初始化;
  private mAssetIds?: Set<string>;

  private mDirectoryManager = new MCAssetDirectoryManager();

  private mSerialPromise: Promise<void> = Promise.resolve();

  prepare(context: Context): Promise<void> {
    return this.mDirectoryManager.prepare(context);
  }

  getAssetByProxyPath(proxyPath: string): Promise<IMCAsset> {
    return this.enqueueTask(async () => {
      const targetInfo = MCProxyUtils.parseTarget(proxyPath);
      const assetType = targetInfo.assetType;
      const assetId = targetInfo.assetId;
      let asset = this.mAssetMap.get(assetId);
      if ( !asset ) {
        const assetDirPath = this.mDirectoryManager.resolveDirPath(assetId, assetType);
        asset = (assetType === MCAssetType.FILE_BASED) ? new FILEAsset(assetId, assetDirPath) : new HLSAsset(assetId, assetDirPath);
        try {
          await asset.prepare();
        }
        catch (e) {
          throw new Error(`Asset prepare failed with error: ${e}`);
        }

        this.mAssetMap.set(assetId, asset);
        this.mSizeMap.delete(assetId);
        this.mAssetIds?.add(assetId);
      }
      return asset;
    });
  }

  removeAssetBy(assetId: string): Promise<void> {
    return this.enqueueTask(async () => {
      let asset = this.mAssetMap.get(assetId);
      if ( asset ) {
        await asset.abort(new Error(`Asset ${assetId} is being removed`));
      }

      let assetDirPath: string | undefined;
      if ( asset ) {
        assetDirPath = this.mDirectoryManager.resolveDirPath(asset.id, asset.type);
      }
      else {
        assetDirPath = await this.mDirectoryManager.findDirPath(assetId);
      }

      if ( assetDirPath ) {
        await MCFileIOUtils.deleteAllFiles(assetDirPath);
      }

      this.mAssetMap.delete(assetId);
      this.mSizeMap.delete(assetId);
      this.mAssetIds?.delete(assetId);
    });
  }

  getAllAssetIds(): Promise<string[]> {
    return this.enqueueTask(async () => {
      if ( this.mAssetIds ) {
        return Array.from(this.mAssetIds);
      }

      const ids = await this.mDirectoryManager.getAllAssetIds();
      this.mAssetIds = new Set();
      for (let id of ids) {
        this.mAssetIds.add(id);
      }
      return ids;
    });
  }

  calculateCacheSize(assetId: string): Promise<number> {
    return this.enqueueTask(async () => {
      const asset = this.mAssetMap.get(assetId);
      if ( asset ) {
        return asset.currentCachedSize;
      }

      let size = this.mSizeMap.get(assetId);
      if ( size != undefined ) {
        return size;
      }

      size = await this.mDirectoryManager.calculateSize(assetId);
      this.mSizeMap.set(assetId, size);
      return size;
    })
  }

  calculateCacheSizeForAssets(assetIds: string[]): Promise<number> {
    return this.enqueueTask(async () => {
      let totalSize = 0;
      const missingIds: string[] = [];
      for ( let id of assetIds ) {
        const asset = this.mAssetMap.get(id);
        if ( asset ) {
          totalSize += asset.currentCachedSize;
          continue;
        }

        const size = this.mSizeMap.get(id);
        if ( size != undefined ) {
          totalSize += size;
          continue;
        }

        missingIds.push(id);
      }

      if ( missingIds.length > 0 ) {
        const sizes = await this.mDirectoryManager.calculateSizeForAssets(missingIds);
        for (let pair of sizes) {
          this.mSizeMap.set(pair[0], pair[1]);
          totalSize += pair[1];
        }
      }
      return totalSize;
    });
  }

  private enqueueTask<T>(task: () => Promise<T>): Promise<T> {
    const run = this.mSerialPromise
      .catch((err: Error) => {  // swallow previous errors
        console.error('Previous task failed:', err);
      })
      .then(() => task());

    // Maintain the chain
    this.mSerialPromise = run.then(() => {}, (err: Error) => {
      console.error('Previous task failed:', err);
    });
    return run;
  }
}