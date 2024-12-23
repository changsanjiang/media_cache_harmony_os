import { MCPreferences } from "../../utils/MCPreferences";
import MCUtils from "../../utils/MCUtils";
import { MCAssetAccessLog2 } from "./MCAssetAccessLog";

/** 记录访问日志; 例如最后一次的访问时间; */
namespace MCAssetAccessLogRepository {
  const mLogs = new Map<string, MCAssetAccessLog2>();
  const mPref = new MCPreferences<string>('mc_asset_access_pref');

  export async function prepare(): Promise<void> {
    const record = await mPref.getAll();
    const map = MCUtils.recordToMap(record);
    for (let element of Array.from(map.entries())) {
      try {
        const assetId = element[0];
        const log = JSON.parse(element[1]) as MCAssetAccessLog2;
        mLogs.set(assetId, log);
      }
      catch (ignored) { }
    }
  }

  export async function onAccess(assetId: string): Promise<void> {
    const now = Date.now();
    let log = mLogs.get(assetId);
    if ( log && log.lastAccessed === now ) return;

    if ( !log ) {
      log = {
        firstAccessed: now,
        lastAccessed: now
      }
      mLogs.set(assetId, log);
    }
    else {
      log.lastAccessed = now;
    }

    await mPref.set(assetId, JSON.stringify(log));
    await mPref.flush();
  }

  export async function onEvict(assetId: string): Promise<void> {
    if ( mLogs.get(assetId) ) {
      mLogs.delete(assetId);
      await mPref.delete(assetId);
      await mPref.flush();
    }
  }

  export function filter(predicate: (pair: [string, MCAssetAccessLog2]) => boolean): [string, MCAssetAccessLog2][] {
    return Array.from(mLogs.entries()).filter(predicate);
  }

  export function getCount(): number {
    return mLogs.size;
  }
}

export default MCAssetAccessLogRepository;