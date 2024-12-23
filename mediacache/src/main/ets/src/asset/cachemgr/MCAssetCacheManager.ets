import { IMCAsset } from "../../defines/IMCAsset";
import MCConfigs from '../../utils/MCConfigs';
import MCAssetManager from "../MCAssetManager";
import MCFileIOUtils from "../../utils/MCFileIOUtils";
import MCAssetStateRepository from "../cachestate/MCAssetStateRepository";
import MCAssetUtils from "../MCAssetUtils";
import MCAssetAccessLogRepository from "../cachestate/MCAssetAccessLogRepository";
import { MCAssetCacheConfig } from "../../defines/MCAssetCacheConfig";

namespace MCAssetCacheManager {
  enum Limit {
    COUNT,
    DISK_AGE,
    DISK_SIZE,
    DISK_SPACE_WARNING, // 磁盘空间预警
  }

  export const config = new MCAssetCacheConfig();
  let mPeriodTrimStarted = false;

  export async function prepare(): Promise<void> {
    await MCAssetStateRepository.prepare();
    await MCAssetAccessLogRepository.prepare();

    trimAssetsBy(Limit.COUNT);
    trimAssetsBy(Limit.DISK_AGE);
    trimAssetsBy(Limit.DISK_SIZE);
    trimAssetsBy(Limit.DISK_SPACE_WARNING);
  }

  export async function onAssetReadwrite(asset: IMCAsset): Promise<void> {
    await MCAssetAccessLogRepository.onAccess(asset.id);
    startPeriodTrim();
  }

  export async function setPinned(resUrl: string, isPinned: boolean): Promise<void> {
    const assetId = await MCAssetUtils.generateAssetId(resUrl);
    await MCAssetStateRepository.setPinned(assetId, isPinned);
  }

  export async function isPinned(resUrl: string): Promise<boolean> {
    const assetId = await MCAssetUtils.generateAssetId(resUrl);
    return MCAssetStateRepository.isPinned(assetId);
  }

  export async function countOfBytesAllCaches(): Promise<number> {
    const allIds = await MCAssetManager.queryAllAssetIds();
    return allIds.length > 0 ? MCAssetManager.calculateCacheSizeForAssets(allIds) : 0;
  }

  export async function countOfBytesPinnedCaches(): Promise<number> {
    const allIds = await MCAssetManager.queryAllAssetIds();
    const pinnedAssets = allIds.filter(assetId => MCAssetStateRepository.isPinned(assetId));
    return pinnedAssets.length > 0 ? MCAssetManager.calculateCacheSizeForAssets(pinnedAssets) : 0;
  }

  export async function removeCacheBy(resUrl: string): Promise<void> {
    const assetId = await MCAssetUtils.generateAssetId(resUrl);
    return evictAssets([assetId]);
  }

  export async function removeCaches(): Promise<void> {
    const allIds = await MCAssetManager.queryAllAssetIds();
    const assetsToEvict = allIds.filter(assetId => !MCAssetStateRepository.isPinned(assetId));;
    return evictAssets(assetsToEvict);
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
        if ( config.assetCountLimit === 0 ) {
          return;
        }

        const sortedByAccess = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0])).sort((a, b) => a[1].lastAccessed - b[1].lastAccessed);
        const count = sortedByAccess.length - config.assetCountLimit;
        if ( count > 0 ) {
          const assetsToEvict = sortedByAccess.slice(0, count).map(pair => pair[0]);
          return evictAssets(assetsToEvict);
        }
      }
        break;
      case Limit.DISK_AGE: {
        if (config.assetMaxDiskAge === 0) {
          return;
        }

        const now = Date.now();
        const expiredAssets = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0]) && ((now - pair[1].firstAccessed) > config.assetMaxDiskAge)).map(pair => pair[0]);
        if (expiredAssets.length > 0) {
          await evictAssets(expiredAssets);
        }
      }
        break;
      case Limit.DISK_SIZE: {
        if ( config.assetsMaxDiskSize === 0 ) {
          return;
        }

        const sortedByAccess = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0])).sort((a, b) => a[1].lastAccessed - b[1].lastAccessed).map(pair => pair[0]);
        const totalSize = await MCAssetManager.calculateCacheSizeForAssets(sortedByAccess);
        if ( totalSize > config.assetsMaxDiskSize ) {
          await evictAssetsBySize(totalSize - config.assetsMaxDiskSize);
        }
      }
        break;
      case Limit.DISK_SPACE_WARNING: {
        if (config.diskSpaceWarningThreshold === 0) {
          return;
        }

        const freeSpace = await getDiskFreeSpace();
        if (freeSpace < config.diskSpaceWarningThreshold) {
          // console.warn(`Disk space low: ${freeSpace} bytes available.`);
          await evictAssetsBySize(config.diskSpaceWarningThreshold - freeSpace);
        }
      }
        break;
    }
  }

  async function evictAssetsBySize(size: number): Promise<void> {
    const sortedByAccess = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0])).sort((a, b) => a[1].lastAccessed - b[1].lastAccessed);
    const assetsToEvict: string[] = [];
    let cacheSize = 0;
    for (const pair of sortedByAccess) {
      if (cacheSize > size) break;
      assetsToEvict.push(pair[0]);
      cacheSize += await MCAssetManager.calculateCacheSize(pair[0]);
    }
    return evictAssets(assetsToEvict);
  }

  async function evictAssets(assetIds: string[]): Promise<void> {
    if ( assetIds.length > 0 ) {
      for (const assetId of assetIds) {
        await MCAssetAccessLogRepository.onEvict(assetId);
        await MCAssetStateRepository.onEvict(assetId);
        await MCAssetManager.removeAssetBy(assetId);
      }
    }
  }

  function getDiskFreeSpace(): Promise<number> {
    return MCFileIOUtils.getFreeSize(MCConfigs.context.filesDir);
  }
}

export default MCAssetCacheManager;