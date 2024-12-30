import { MCLogModule } from "../../defines/MCLogModule";
import MCLogger from "../../utils/MCLogger";
import { MCPreferences } from "../../utils/MCPreferences";
import MCUtils from "../../utils/MCUtils";
import { MCAssetAccessLog } from "./MCAssetAccessLog";

/** 记录访问日志; 例如最后一次的访问时间; */
namespace MCAssetAccessLogRepository {
  const mLogs = new Map<string, MCAssetAccessLog>();
  const mPref = new MCPreferences<string>('mc_asset_access_pref');

  // 初始化和加载访问日志
  export async function prepare(): Promise<void> {
    try {
      const record = await mPref.getAll();
      const map = MCUtils.recordToMap(record);
      for (let element of Array.from(map.entries())) {
        try {
          const assetId = element[0];
          const log = JSON.parse(element[1]) as MCAssetAccessLog;
          mLogs.set(assetId, log);
          MCLogger.debug(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${assetId}] Loaded access log. FirstAccessed: ${log.firstAccessed}, LastAccessed: ${log.lastAccessed}`);
        }
        catch (ignored) {
          MCLogger.warn(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${element[0]}] Failed to parse access log entry with content: ${element[1]}`);
        }
      }

      MCLogger.info(MCLogModule.MCAssetAccessLogRepository, () => `Asset access logs initialized. Total loaded: ${mLogs.size}`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetAccessLogRepository, () => `[Error] Failed to prepare asset access logs: ${error.message}`);
      throw error as Error;
    }
  }

  // 记录资产访问，更新访问时间
  export async function onAccess(assetId: string): Promise<void> {
    const now = Date.now();
    let log = mLogs.get(assetId);
    if ( log && log.lastAccessed === now ) return;

    if ( !log ) {
      log = { firstAccessed: now, lastAccessed: now }
      mLogs.set(assetId, log);
      MCLogger.info(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${assetId}] First access recorded at ${now}.`);
    }
    else {
      log.lastAccessed = now;
      MCLogger.info(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${assetId}] Updated last accessed time to ${now}.`);
    }

    try {
      await mPref.set(assetId, JSON.stringify(log));
      await mPref.flush();
      MCLogger.debug(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${assetId}] Saved access log to preferences.`);
    } catch (error) {
      MCLogger.error(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${assetId}] Failed to save access log: ${error.message}`);
      throw error as Error;
    }
  }

  // 清除缓存中的资产访问日志
  export async function onEvict(assetId: string): Promise<void> {
    if ( mLogs.get(assetId) ) {
      mLogs.delete(assetId);
      try {
        await mPref.delete(assetId);
        await mPref.flush();
        MCLogger.info(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${assetId}] Evicted access log and cleared preferences.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${assetId}] Failed to evict access log: ${error.message}`);
        throw error as Error;
      }
    }
    else {
      MCLogger.warn(MCLogModule.MCAssetAccessLogRepository, () => `[AssetId: ${assetId}] No access log found to evict.`);
    }
  }

  // 根据条件过滤访问日志
  export function filter(predicate: (pair: [string, MCAssetAccessLog]) => boolean): [string, MCAssetAccessLog][] {
    const filteredLogs = Array.from(mLogs.entries()).filter(predicate);
    MCLogger.debug(MCLogModule.MCAssetAccessLogRepository, () => `Filtered logs based on predicate. Result count: ${filteredLogs.length}`);
    return filteredLogs;
  }

  // 获取日志条数
  export function getCount(): number {
    const count = mLogs.size;
    MCLogger.debug(MCLogModule.MCAssetAccessLogRepository, () => `Current access log count: ${count}`);
    return count;
  }
}

export default MCAssetAccessLogRepository;