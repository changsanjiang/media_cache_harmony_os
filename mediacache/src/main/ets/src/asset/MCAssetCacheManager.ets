import { IMCAsset } from "../defines/IMCAsset";
import { MCPreferences } from "../utils/MCPreferences";
import MCConfigs from '../utils/MCConfigs';
import { statfs } from '@kit.CoreFileKit';

namespace MCAssetCacheManager {
  interface AccessLog {
    firstAccessed: string;    // 首次读写时间
    lastAccessed: string      // 最后一次访问的时间
  }

  enum Limit {
    COUNT,
    DISK_AGE,
    DISK_SIZE,
    DISK_SPACE_WARNING, // 磁盘空间预警
  }

  const mPref = new MCPreferences<string>('mc_access_pref');

  const mLogs = new Map<IMCAsset, AccessLog>();

  /** Asset 个数限制; */
  export let assetCountLimit: number = 0;

  /** Asset 保存时长限制(单位: 毫秒); */
  export let assetMaxDiskAge: number = 0;

  /** 所有缓存占用的磁盘空间限制(单位: 字节); */
  export let allAssetsMaxDiskSize: number = 0;

  /** 磁盘空间预警阈值(单位: 字节); */
  export let diskSpaceWarningThreshold: number = 1024 * 1024 * 1024; // 默认 1G;

  export async function prepare(): Promise<void> {
    // mPref.getAll()
  }

  export async function onAssetReadwrite(asset: IMCAsset): Promise<void> {
    const now = Date.now().toString();
    let log = mLogs.get(asset);
    if ( log && log.lastAccessed === now ) return;

    if ( !log ) {
      log = {
        firstAccessed: now,
        lastAccessed: now
      }
      mLogs.set(asset, log);
    }
    else {
      log.lastAccessed = now;
    }

    return mPref.set(asset.id, JSON.stringify(log));
  }

  async function trimAssetsBy(limit: Limit): Promise<void> {
    switch (limit) {
      case Limit.COUNT: {
        if ( assetCountLimit === 0 ) {
          return;
        }

        const count = mLogs.size;
        if ( count > assetCountLimit ) {
          await evictAssetsByCount(count - assetCountLimit);
        }
      }
        break;
      case Limit.DISK_AGE: {
        if (assetMaxDiskAge === 0) {
          return;
        }

        const now = Date.now();
        const expiredAssets = Array.from(mLogs.entries()).filter(pair => (now - parseInt(pair[1].firstAccessed) > assetMaxDiskAge)).map(pair => pair[0]);
        if (expiredAssets.length > 0) {
          await evictAssets(expiredAssets);
        }
      }
        break;
      case Limit.DISK_SIZE: {
        if ( allAssetsMaxDiskSize === 0 ) {
          return;
        }

        let totalSize = Array.from(mLogs.keys()).reduce((prev, a) => prev + a.cacheSize, 0);
        if (totalSize > allAssetsMaxDiskSize) {
          await evictAssetsBySize(totalSize - allAssetsMaxDiskSize);
        }
      }
        break;
      case Limit.DISK_SPACE_WARNING: {
        if (diskSpaceWarningThreshold === 0) {
          return;
        }

        const freeSpace = await getDiskFreeSpace();
        if (freeSpace < diskSpaceWarningThreshold) {
          // console.warn(`Disk space low: ${freeSpace} bytes available.`);
          await evictAssetsBySize(diskSpaceWarningThreshold - freeSpace);
        }
      }
        break;
    }
  }

  function evictAssetsBySize(size: number): Promise<void> {
    // 根据 size 和 lastAccessed 排序，优先移除较旧且大的文件
    const sortedAssets = Array.from(mLogs.entries()).sort((a, b) => {
      const a1 = parseInt(a[1].lastAccessed);
      const b1 = parseInt(b[1].lastAccessed);
      if ( a1 !== b1 ) {
        return a1 - b1; // 先按访问时间排序
      }
      return b[0].cacheSize - a[0].cacheSize; // 再按大小排序
    });

    const assetsToEvict: IMCAsset[] = [];
    let cacheSize = 0;
    for (const pair of sortedAssets) {
      if (cacheSize > size) break;
      assetsToEvict.push(pair[0]);
      cacheSize += pair[0].cacheSize;
    }
    return evictAssets(assetsToEvict);
  }

  function evictAssetsByCount(count: number): Promise<void> {
    const sortedByAccess = Array.from(mLogs.entries()).sort((a, b) => parseInt(a[1].lastAccessed) - parseInt(b[1].lastAccessed));
    const assetsToEvict = sortedByAccess.slice(0, count).map(pair => pair[0]);
    return evictAssets(assetsToEvict);
  }

  async function evictAssets(assets: IMCAsset[]): Promise<void> {
    for (const a of assets) {
      // TODO() next ...
      // a.destroy() ...
      mLogs.delete(a);
      await mPref.delete(a.id);
    }
    return mPref.flush();
  }

  function getDiskFreeSpace(): Promise<number> {
    let path = MCConfigs.context.filesDir;
    return statfs.getFreeSize(path);
  }
}

export default MCAssetCacheManager;