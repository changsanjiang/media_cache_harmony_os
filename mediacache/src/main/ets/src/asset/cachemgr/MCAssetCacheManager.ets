import { IMCAsset } from "../../defines/IMCAsset";
import MCConfigs from '../../utils/MCConfigs';
import { statfs } from '@kit.CoreFileKit';
import MCAssetCacheConfig from "./MCAssetCacheConfig";
import MCAssetStateManager from "./MCAssetStateManager";
import MCAssetAccessLogManager from "./MCAssetAccessLogManager";

namespace MCAssetCacheManager {
  enum Limit {
    COUNT,
    DISK_AGE,
    DISK_SIZE,
    DISK_SPACE_WARNING, // 磁盘空间预警
  }

  let mPeriodTrimStarted = false;

  export async function prepare(): Promise<void> {
    await MCAssetStateManager.prepare();
    await MCAssetAccessLogManager.prepare();

    trimAssetsBy(Limit.COUNT);
    trimAssetsBy(Limit.DISK_AGE);
    trimAssetsBy(Limit.DISK_SIZE);
    trimAssetsBy(Limit.DISK_SPACE_WARNING);
  }

  export async function onAssetReadwrite(asset: IMCAsset): Promise<void> {
    await MCAssetAccessLogManager.onAccess(asset);
    MCAssetAccessLogManager.startFlushAfter(5 * 1000);
    startPeriodTrim();
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
        if ( MCAssetCacheConfig.assetCountLimit === 0 ) {
          return;
        }

        const count = MCAssetAccessLogManager.getCount();
        if ( count > MCAssetCacheConfig.assetCountLimit ) {
          await evictAssetsByCount(count - MCAssetCacheConfig.assetCountLimit);
        }
      }
        break;
      case Limit.DISK_AGE: {
        if (MCAssetCacheConfig.assetMaxDiskAge === 0) {
          return;
        }

        const now = Date.now();
        const expiredAssets = MCAssetAccessLogManager.filter(pair => !MCAssetStateManager.isPinned(pair[0].id) && (now - parseInt(pair[1].firstAccessed) > MCAssetCacheConfig.assetMaxDiskAge)).map(pair => pair[0]);
        if (expiredAssets.length > 0) {
          await evictAssets(expiredAssets);
        }
      }
        break;
      case Limit.DISK_SIZE: {
        if ( MCAssetCacheConfig.allAssetsMaxDiskSize === 0 ) {
          return;
        }

        let totalSize = MCAssetAccessLogManager.filter(pair => !MCAssetStateManager.isPinned(pair[0].id)).reduce((prev, pair) => prev + pair[0].cacheSize, 0);
        if (totalSize > MCAssetCacheConfig.allAssetsMaxDiskSize) {
          await evictAssetsBySize(totalSize - MCAssetCacheConfig.allAssetsMaxDiskSize);
        }
      }
        break;
      case Limit.DISK_SPACE_WARNING: {
        if (MCAssetCacheConfig.diskSpaceWarningThreshold === 0) {
          return;
        }

        const freeSpace = await getDiskFreeSpace();
        if (freeSpace < MCAssetCacheConfig.diskSpaceWarningThreshold) {
          // console.warn(`Disk space low: ${freeSpace} bytes available.`);
          await evictAssetsBySize(MCAssetCacheConfig.diskSpaceWarningThreshold - freeSpace);
        }
      }
        break;
    }
  }

  function evictAssetsBySize(size: number): Promise<void> {
    // 根据 size 和 lastAccessed 排序，优先移除较旧且大的文件
    const sortedAssets = MCAssetAccessLogManager.filter(pair => !MCAssetStateManager.isPinned(pair[0].id)).sort((a, b) => {
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
    const sortedByAccess = MCAssetAccessLogManager.filter((pair) => !MCAssetStateManager.isPinned(pair[0].id)).sort((a, b) => parseInt(a[1].lastAccessed) - parseInt(b[1].lastAccessed));
    const assetsToEvict = sortedByAccess.slice(0, count).map(pair => pair[0]);
    return evictAssets(assetsToEvict);
  }

  async function evictAssets(assets: IMCAsset[]): Promise<void> {
    for (const a of assets) {
      await MCAssetAccessLogManager.onEvict(a);
      await a.removeAllCaches();
    }
    await MCAssetAccessLogManager.flush();
  }

  function getDiskFreeSpace(): Promise<number> {
    let path = MCConfigs.context.filesDir;
    return statfs.getFreeSize(path);
  }
}

export default MCAssetCacheManager;