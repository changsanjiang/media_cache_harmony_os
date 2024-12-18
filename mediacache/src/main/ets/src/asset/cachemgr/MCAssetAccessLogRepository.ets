import { IMCAsset } from "../../defines/IMCAsset";
import { MCPreferences } from "../../utils/MCPreferences";
import MCUtils from "../../utils/MCUtils";
import { MCAssetAccessLog } from "./MCAssetAccessLog";
import MCAssetManager from "../MCAssetManager";

namespace MCAssetAccessLogRepository {
  const mLogs = new Map<IMCAsset, MCAssetAccessLog>();
  const mPref = new MCPreferences<string>('mc_asset_access_pref');
  let mFlushId: number | undefined = undefined;
  let mPrepared = false;

  export async function prepare(): Promise<void> {
    if ( !mPrepared ) {
      const record = await mPref.getAll();
      const map = MCUtils.recordToMap(record);
      let shouldFlush = false;
      for (let element of Array.from(map.entries())) {
        try {
          const assetId = element[0];
          const log = JSON.parse(element[1]) as MCAssetAccessLog;
          const asset = await MCAssetManager.getAssetById(assetId);
          if ( asset ) {
            mLogs.set(asset, log);
          }
          else {
            if ( !shouldFlush ) shouldFlush = true;
            mPref.delete(assetId);
          }
        }
        catch (ignored) { }
      }
      if ( shouldFlush ) await mPref.flush();
      mPrepared = true;
    }
  }

  export async function onAccess(asset: IMCAsset): Promise<void> {
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

    await mPref.set(asset.id, JSON.stringify(log));
  }

  export async function onEvict(asset: IMCAsset): Promise<void> {
    mLogs.delete(asset);
    await mPref.delete(asset.id);
  }

  export function filter(predicate: (pair: [IMCAsset, MCAssetAccessLog]) => boolean): [IMCAsset, MCAssetAccessLog][] {
    return Array.from(mLogs.entries()).filter(predicate);
  }

  export function getCount(): number {
    return mLogs.size;
  }

  export function deferFlush(delay: number = 5 * 1000) {
    if ( mFlushId === undefined ) {
      mFlushId = setTimeout(() => flush(), delay);
    }
  }

  export async function flush(): Promise<void> {
    if ( mFlushId !== undefined ) {
      clearTimeout(mFlushId);
      mFlushId = undefined;
      return mPref.flush();
    }
  }
}

export default MCAssetAccessLogRepository;