import { IMCAsset } from "../../defines/IMCAsset";
import MCConfigs from '../../utils/MCConfigs';
import MCAssetManager from "../MCAssetManager";
import MCFileIOUtils from "../../utils/MCFileIOUtils";
import MCAssetStateRepository from "../cachestate/MCAssetStateRepository";
import MCAssetUtils from "../MCAssetUtils";
import MCAssetAccessLogRepository from "../cachestate/MCAssetAccessLogRepository";
import { MCAssetCacheConfig } from "../../defines/MCAssetCacheConfig";
import MCLogger from "../../utils/MCLogger";
import { MCLogModule } from "../../defines/MCLogModule";

namespace MCAssetCacheManager {
  enum Limit {
    COUNT,
    DISK_AGE,
    DISK_SIZE,
    DISK_SPACE_WARNING, // 磁盘空间预警
  }

  export const config = new MCAssetCacheConfig();
  let mPeriodTrimStarted = false;

  /** 初始化缓存管理器 */
  export async function prepare(): Promise<void> {
    try {
      MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Initializing asset cache manager.`);
      await MCAssetStateRepository.prepare();
      await MCAssetAccessLogRepository.prepare();

      MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Starting initial asset trimming.`);
      await trimAssetsBy(Limit.COUNT);
      await trimAssetsBy(Limit.DISK_AGE);
      await trimAssetsBy(Limit.DISK_SIZE);
      await trimAssetsBy(Limit.DISK_SPACE_WARNING);
      MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Asset cache manager initialized.`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Failed to initialize asset cache manager: ${error.message}`);
      throw error as Error;
    }
  }

  /** 读写资产时记录访问 */
  export async function onAssetReadwrite(asset: IMCAsset): Promise<void> {
    MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${asset.id}] Access recorded.`);
    await MCAssetAccessLogRepository.onAccess(asset.id);
    startPeriodTrim();
  }

  /** 设置资产固定状态 */
  export async function setPinned(resUrl: string, isPinned: boolean): Promise<void> {
    try {
      const assetId = await MCAssetUtils.generateAssetId(resUrl);
      await MCAssetStateRepository.setPinned(assetId, isPinned);
      MCLogger.info(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${assetId}] Set pinned state to: ${isPinned}`);
    } catch (error) {
      MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Failed to set pinned state for [ResUrl: ${resUrl}]: ${error.message}`);
      throw error as Error;
    }
  }

  /** 检查资产是否固定 */
  export async function isPinned(resUrl: string): Promise<boolean> {
    try {
      const assetId = await MCAssetUtils.generateAssetId(resUrl);
      const pinned = MCAssetStateRepository.isPinned(assetId);
      MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${assetId}] isPinned query result: ${pinned}`);
      return pinned;
    } catch (error) {
      MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Failed to check pinned state for [ResUrl: ${resUrl}]: ${error.message}`);
      throw error as Error;
    }
  }

  /** 获取缓存总大小 */
  export async function countOfBytesAllCaches(): Promise<number> {
    try {
      const allIds = await MCAssetManager.queryAllAssetIds();
      const size = allIds.length > 0 ? await MCAssetManager.calculateCacheSizeForAssets(allIds) : 0;
      MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Total cache size calculated: ${size} bytes.`);
      return size;
    } catch (error) {
      MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Failed to calculate total cache size: ${error.message}`);
      throw error as Error;
    }
  }

  /** 获取固定缓存大小 */
  export async function countOfBytesPinnedCaches(): Promise<number> {
    try {
      const allIds = await MCAssetManager.queryAllAssetIds();
      const pinnedAssets = allIds.filter(assetId => MCAssetStateRepository.isPinned(assetId));
      const size = pinnedAssets.length > 0 ? await MCAssetManager.calculateCacheSizeForAssets(pinnedAssets) : 0;
      MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Pinned cache size calculated: ${size} bytes.`);
      return size;
    } catch (error) {
      MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Failed to calculate pinned cache size: ${error.message}`);
      throw error as Error;
    }
  }

  /** 删除单个缓存 */
  export async function removeCacheBy(resUrl: string): Promise<void> {
    try {
      const assetId = await MCAssetUtils.generateAssetId(resUrl);
      await evictAssets([assetId]);
      MCLogger.info(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${assetId}] Cache removed successfully.`);
    } catch (error) {
      MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Failed to remove cache for [ResUrl: ${resUrl}]: ${error.message}`);
      throw error as Error;
    }
  }

  /** 删除所有未固定的缓存 */
  export async function removeCaches(): Promise<void> {
    try {
      const allIds = await MCAssetManager.queryAllAssetIds();
      const assetsToEvict = allIds.filter(assetId => !MCAssetStateRepository.isPinned(assetId));
      await evictAssets(assetsToEvict);
      MCLogger.info(MCLogModule.MCAssetCacheManager, () => `All non-pinned caches removed successfully.`);
    } catch (error) {
      MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Failed to remove caches: ${error.message}`);
      throw error as Error;
    }
  }

  /** 定期触发缓存修剪 */
  function startPeriodTrim() {
    if ( mPeriodTrimStarted ) {
      return;
    }

    mPeriodTrimStarted = true;
    MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Periodic cache trimming started.`);

    // 定期检测

    // 每5分钟检测一次
    setInterval(async () => {
      await trimAssetsBy(Limit.COUNT);
      await trimAssetsBy(Limit.DISK_SIZE);
    }, 5 * 60 * 1000);

    // 每半小时检测一次
    setInterval(async () => {
      await trimAssetsBy(Limit.DISK_AGE);
      await trimAssetsBy(Limit.DISK_SPACE_WARNING);
    }, 30 * 60 * 1000);
  }

  /** 修剪资产 */
  async function trimAssetsBy(limit: Limit): Promise<void> {
    try {
      switch (limit) {
        case Limit.COUNT: {
          MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Trimming assets by count.`);
          if ( config.assetCountLimit === 0 ) {
            MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Asset count limit is 0, skipping trimming by count.`);
            return;
          }

          const sortedByAccess = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0])).sort((a, b) => a[1].lastAccessed - b[1].lastAccessed);
          const count = sortedByAccess.length - config.assetCountLimit;
          if ( count > 0 ) {
            const assetsToEvict = sortedByAccess.slice(0, count).map(pair => pair[0]);
            MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Evicting ${assetsToEvict.length} assets due to count limit.`);
            await evictAssets(assetsToEvict);
          }
          else {
            MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `No assets to evict based on count.`);
          }
        }
          break;
        case Limit.DISK_AGE: {
          MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Trimming assets by disk age.`);
          if ( config.assetMaxDiskAge === 0 ) {
            MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Asset max disk age is 0, skipping trimming by disk age.`);
            return;
          }

          const now = Date.now();
          const expiredAssets = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0]) && ((now - pair[1].firstAccessed) > config.assetMaxDiskAge)).map(pair => pair[0]);
          if ( expiredAssets.length > 0 ) {
            MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Evicting ${expiredAssets.length} expired assets.`);
            await evictAssets(expiredAssets);
          } else {
            MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `No expired assets to evict.`);
          }
        }
          break;
        case Limit.DISK_SIZE: {
          MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Trimming assets by disk size.`);
          if ( config.assetsMaxDiskSize === 0 ) {
            MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Assets max disk size is 0, skipping trimming by disk size.`);
            return;
          }

          const sortedByAccess = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0])).sort((a, b) => a[1].lastAccessed - b[1].lastAccessed).map(pair => pair[0]);
          const totalSize = await MCAssetManager.calculateCacheSizeForAssets(sortedByAccess);
          if ( totalSize > config.assetsMaxDiskSize ) {
            const sizeToEvict = totalSize - config.assetsMaxDiskSize;
            MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Exceeding max disk size by ${sizeToEvict} bytes. Evicting assets.`);
            await evictAssetsBySize(sizeToEvict);
          }
          else {
            MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Total cache size (${totalSize} bytes) within limit.`);
          }
        }
          break;
        case Limit.DISK_SPACE_WARNING: {
          MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Trimming assets by disk space warning.`);
          if ( config.diskSpaceWarningThreshold === 0 ) {
            MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Disk space warning threshold is 0, skipping trimming.`);
            return;
          }

          const freeSpace = await getDiskFreeSpace();
          if ( freeSpace < config.diskSpaceWarningThreshold ) {
            const deficit = config.diskSpaceWarningThreshold - freeSpace;
            MCLogger.warn(MCLogModule.MCAssetCacheManager, () => `Disk space low: ${freeSpace} bytes available, ${deficit} bytes below warning threshold.`);
            await evictAssetsBySize(deficit);
          }
          else {
            MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Disk space sufficient: ${freeSpace} bytes available.`);
          }
        }
          break;
        default:
          MCLogger.warn(MCLogModule.MCAssetCacheManager, () => `Unknown trimming limit: ${limit}. Skipping.`);
          break;
      }
    }
    catch (ignored) {
      MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Error trimming assets by ${Limit[limit]}: ${ignored.message}`);
    }
  }

  /** 移除相应大小的资产 */
  async function evictAssetsBySize(size: number): Promise<void> {
    const sortedByAccess = MCAssetAccessLogRepository.filter(pair => !MCAssetStateRepository.isPinned(pair[0])).sort((a, b) => a[1].lastAccessed - b[1].lastAccessed);
    const assetsToEvict: string[] = [];
    let cacheSize = 0;
    for (const pair of sortedByAccess) {
      if (cacheSize > size) break;
      assetsToEvict.push(pair[0]);
      cacheSize += await MCAssetManager.calculateCacheSize(pair[0]);
    }

    if ( assetsToEvict.length > 0 ) {
      MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Evicting ${assetsToEvict.length} assets to free up ${cacheSize} bytes.`);
      await evictAssets(assetsToEvict);
    }
    else {
      MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `No assets to evict for size trimming.`);
    }
  }

  /** 移除资产 */
  async function evictAssets(assetIds: string[]): Promise<void> {
    if (assetIds.length === 0) {
      MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `No assets to evict.`);
      return;
    }

    MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Starting eviction of ${assetIds.length} asset(s).`);

    for (const assetId of assetIds) {
      MCLogger.info(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${assetId}] Eviction started.`);
      try {
        await MCAssetAccessLogRepository.onEvict(assetId);
        MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${assetId}] Access log evicted.`);

        await MCAssetStateRepository.onEvict(assetId);
        MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${assetId}] State evicted.`);

        await MCAssetManager.removeAssetBy(assetId);
        MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${assetId}] Evicted successfully.`);
      }
      catch (error) {
        MCLogger.warn(MCLogModule.MCAssetCacheManager, () => `[AssetId: ${assetId}] Failed to evict: ${error.message}`);
      }
    }

    MCLogger.info(MCLogModule.MCAssetCacheManager, () => `Eviction of assets completed.`);
  }

  function getDiskFreeSpace(): Promise<number> {
    return MCFileIOUtils.getFreeSize(MCConfigs.context.filesDir)
      .then(space => {
        MCLogger.debug(MCLogModule.MCAssetCacheManager, () => `Disk free space: ${space} bytes.`);
        return space;
      })
      .catch((error: Error) => {
        MCLogger.error(MCLogModule.MCAssetCacheManager, () => `Failed to get disk free space: ${error.message}`);
        throw error;
      });
  }
}

export default MCAssetCacheManager;