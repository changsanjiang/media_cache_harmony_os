import { IMCAsset } from "../../defines/IMCAsset";
import MCConfigs from '../../utils/MCConfigs';
import { statfs } from '@kit.CoreFileKit';
import MCAssetStateRepository from "./MCAssetStateRepository";
import MCAssetAccessLogRepository from "./MCAssetAccessLogRepository";
import MCAssetUtils from "../MCAssetUtils";
import { MCAssetCacheConfig } from "../../defines/MCAssetCacheConfig";
import MCAssetManager from "../MCAssetManager";

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

  export async function countOfBytesAllCaches(): Promise<number> {
    const assets = await MCAssetManager.queryAssets(() => true);
    return assets.reduce((prev, asset) => prev + asset.cacheSize, 0);
  }

  export async function countOfBytesPinnedCaches(): Promise<number> {
    const assets = await MCAssetManager.queryAssets((info) => MCAssetStateRepository.isPinned(info.assetId));
    return assets.reduce((prev, asset) => prev + asset.cacheSize, 0);
  }

  export async function removeCacheBy(resUrl: string): Promise<void> {
    const asset = await MCAssetManager.getAssetByUrl(resUrl);
    return evictAssets([asset]);
  }

  export async function removeCaches(): Promise<void> {
    const assets = await MCAssetManager.queryAssets((info) => !MCAssetStateRepository.isPinned(info.assetId));
    return evictAssets(assets);
  }

  export async function onAssetReadwrite(asset: IMCAsset): Promise<void> {
    await MCAssetAccessLogRepository.onAccess(asset);
    MCAssetAccessLogRepository.deferFlush(5 * 1000);
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

        const count = MCAssetAccessLogRepository.getCount();
        if ( count > config.assetCountLimit ) {
          await evictAssetsByCount(count - config.assetCountLimit);
        }
      }
        break;
      case Limit.DISK_AGE: {
        if (config.assetMaxDiskAge === 0) {
          return;
        }

        const now = Date.now();
        const expiredAssets = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0].id) && (now - parseInt(pair[1].firstAccessed) > config.assetMaxDiskAge)).map(pair => pair[0]);
        if (expiredAssets.length > 0) {
          await evictAssets(expiredAssets);
        }
      }
        break;
      case Limit.DISK_SIZE: {
        if ( config.allAssetsMaxDiskSize === 0 ) {
          return;
        }

        let totalSize = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0].id)).reduce((prev, pair) => prev + pair[0].cacheSize, 0);
        if (totalSize > config.allAssetsMaxDiskSize) {
          await evictAssetsBySize(totalSize - config.allAssetsMaxDiskSize);
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

  function evictAssetsBySize(size: number): Promise<void> {
    // 根据 size 和 lastAccessed 排序，优先移除较旧且大的文件
    const sortedAssets = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0].id)).sort((a, b) => {
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
    const sortedByAccess = MCAssetAccessLogRepository.filter((pair) => !MCAssetStateRepository.isPinned(pair[0].id)).sort((a, b) => parseInt(a[1].lastAccessed) - parseInt(b[1].lastAccessed));
    const assetsToEvict = sortedByAccess.slice(0, count).map(pair => pair[0]);
    return evictAssets(assetsToEvict);
  }

  async function evictAssets(assets: IMCAsset[]): Promise<void> {
    if ( assets.length > 0 ) {
      for (const a of assets) {
        await MCAssetAccessLogRepository.onEvict(a);
        await a.removeAllCaches();
      }
      await MCAssetAccessLogRepository.flush();
    }
  }

  function getDiskFreeSpace(): Promise<number> {
    let path = MCConfigs.context.filesDir;
    return statfs.getFreeSize(path);
  }
}

export default MCAssetCacheManager;