import { IMCAsset } from "../defines/IMCAsset";
import { MCPreferences } from "../utils/MCPreferences";
import MCConfigs from '../utils/MCConfigs';
import { statfs } from '@kit.CoreFileKit';
import { MCUtils } from '../../../../../Index';
import MCAssetManager from './MCAssetManager';
import MCCacheConfig from "./MCCacheConfig";
import MCAssetStateManager from "./MCAssetStateManager";

namespace MCCacheManager {
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

  const mLogs = new Map<IMCAsset, AccessLog>();
  const mPref = new MCPreferences<string>('mc_cache_access_pref');
  let mPeriodTrimStarted = false;
  let mFlushId: number | undefined = undefined;

  export async function prepare(): Promise<void> {
    const record = await mPref.getAll();
    const map = MCUtils.recordToMap(record);
    let shouldFlush = false;
    for (let element of Array.from(map.entries())) {
      const assetId = element[0];
      const log = JSON.parse(element[1]) as AccessLog;
      const asset = await MCAssetManager.getAsset(assetId);
      if ( asset ) {
        mLogs.set(asset, log);
      }
      else {
        if ( !shouldFlush ) shouldFlush = true;
        mPref.delete(assetId);
      }
    }
    if ( shouldFlush ) await mPref.flush();

    trimAssetsBy(Limit.COUNT);
    trimAssetsBy(Limit.DISK_AGE);
    trimAssetsBy(Limit.DISK_SIZE);
    trimAssetsBy(Limit.DISK_SPACE_WARNING);
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

    startPeriodTrim();
    mPref.set(asset.id, JSON.stringify(log));
    startFlushAfter(5 * 1000);
  }

  function startPeriodTrim() {
    if ( mPeriodTrimStarted ) {
      return;
    }

    mPeriodTrimStarted = true;

    // 定期检测

    // 每5分钟检测一次
    setInterval(() => {
      trimAssetsBy(Limit.COUNT);
      trimAssetsBy(Limit.DISK_SIZE);
    }, 5 * 60 * 1000);

    // 每半小时检测一次
    setInterval(() => {
      trimAssetsBy(Limit.DISK_AGE);
      trimAssetsBy(Limit.DISK_SPACE_WARNING);
    }, 30 * 60 * 1000);
  }

  async function trimAssetsBy(limit: Limit): Promise<void> {
    switch (limit) {
      case Limit.COUNT: {
        if ( MCCacheConfig.assetCountLimit === 0 ) {
          return;
        }

        const count = mLogs.size;
        if ( count > MCCacheConfig.assetCountLimit ) {
          await evictAssetsByCount(count - MCCacheConfig.assetCountLimit);
        }
      }
        break;
      case Limit.DISK_AGE: {
        if (MCCacheConfig.assetMaxDiskAge === 0) {
          return;
        }

        const now = Date.now();
        const expiredAssets = Array.from(mLogs.entries()).filter(pair => !MCAssetStateManager.isPinned(pair[0].id) && (now - parseInt(pair[1].firstAccessed) > MCCacheConfig.assetMaxDiskAge)).map(pair => pair[0]);
        if (expiredAssets.length > 0) {
          await evictAssets(expiredAssets);
        }
      }
        break;
      case Limit.DISK_SIZE: {
        if ( MCCacheConfig.allAssetsMaxDiskSize === 0 ) {
          return;
        }

        let totalSize = Array.from(mLogs.keys()).filter((a) => !MCAssetStateManager.isPinned(a.id)).reduce((prev, a) => prev + a.cacheSize, 0);
        if (totalSize > MCCacheConfig.allAssetsMaxDiskSize) {
          await evictAssetsBySize(totalSize - MCCacheConfig.allAssetsMaxDiskSize);
        }
      }
        break;
      case Limit.DISK_SPACE_WARNING: {
        if (MCCacheConfig.diskSpaceWarningThreshold === 0) {
          return;
        }

        const freeSpace = await getDiskFreeSpace();
        if (freeSpace < MCCacheConfig.diskSpaceWarningThreshold) {
          // console.warn(`Disk space low: ${freeSpace} bytes available.`);
          await evictAssetsBySize(MCCacheConfig.diskSpaceWarningThreshold - freeSpace);
        }
      }
        break;
    }
  }

  function evictAssetsBySize(size: number): Promise<void> {
    // 根据 size 和 lastAccessed 排序，优先移除较旧且大的文件
    const sortedAssets = Array.from(mLogs.entries()).filter((pair) => !MCAssetStateManager.isPinned(pair[0].id)).sort((a, b) => {
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
    const sortedByAccess = Array.from(mLogs.entries()).filter((pair) => !MCAssetStateManager.isPinned(pair[0].id)).sort((a, b) => parseInt(a[1].lastAccessed) - parseInt(b[1].lastAccessed));
    const assetsToEvict = sortedByAccess.slice(0, count).map(pair => pair[0]);
    return evictAssets(assetsToEvict);
  }

  async function evictAssets(assets: IMCAsset[]): Promise<void> {
    for (const a of assets) {
      mLogs.delete(a);
      mPref.delete(a.id);
      a.removeAllCaches();
    }
    return flush();
  }

  function getDiskFreeSpace(): Promise<number> {
    let path = MCConfigs.context.filesDir;
    return statfs.getFreeSize(path);
  }

  function startFlushAfter(delay: number) {
    if ( mFlushId === undefined ) {
      mFlushId = setTimeout(() => flush(), delay);
    }
  }

  async function flush(): Promise<void> {
    if ( mFlushId !== undefined ) {
      clearTimeout(mFlushId);
      mFlushId = undefined;
      return mPref.flush();
    }
  }
}

export default MCCacheManager;