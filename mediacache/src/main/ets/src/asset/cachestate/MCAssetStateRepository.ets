import { MCLogModule } from "../../defines/MCLogModule";
import MCLogger from "../../utils/MCLogger";
import { MCPreferences } from "../../utils/MCPreferences";
import MCUtils from "../../utils/MCUtils";
import { MCAssetState } from "./MCAssetState";

/** 记录资源状态; 例如是否固定; */
namespace MCAssetStateRepository {
  const mStates = new Map<string, MCAssetState>();
  const mPref = new MCPreferences<string>('mc_asset_state_pref');

  // 初始化加载资产状态
  export async function prepare(): Promise<void> {
    try {
      const record = await mPref.getAll();
      const map = MCUtils.recordToMap(record);

      for ( let element of Array.from(map.entries()) ) {
        try {
          const assetId = element[0];
          const state = JSON.parse(element[1]) as MCAssetState;
          mStates.set(assetId, state);
          MCLogger.debug(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${assetId}] Loaded state. IsPinned: ${state.isPinned}`);
        }
        catch (ignored) {
          MCLogger.warn(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${element[0]}] Failed to parse state entry.`);
        }
      }

      MCLogger.info(MCLogModule.MCAssetStateRepository, () => `Asset states initialized. Total loaded: ${mStates.size}`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetStateRepository, () => `Failed to initialize asset states: ${error.message}. Stack trace: ${error.stack}`);
      throw error as Error;
    }
  }

  // 判断资产是否被固定
  export function isPinned(assetId: string): boolean {
    const pinned = mStates.get(assetId)?.isPinned ?? false;
    MCLogger.debug(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${assetId}] isPinned query result: ${pinned}`);
    return pinned;
  }

  // 设置资产的固定状态
  export async function setPinned(assetId: string, isPinned: boolean): Promise<void> {
    try {
      const state: MCAssetState = { isPinned: isPinned };
      mStates.set(assetId, state);
      MCLogger.info(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${assetId}] Set pinned state to: ${isPinned}`);

      await mPref.set(assetId, JSON.stringify(state));
      await mPref.flush();
      MCLogger.debug(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${assetId}] Pinned state saved to preferences.`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${assetId}] Failed to set pinned state: ${error.message}. Stack trace: ${error.stack}`);
      throw error as Error;
    }
  }

  // 删除资产状态
  export async function onEvict(assetId: string): Promise<void> {
    if ( mStates.has(assetId) ) {
      try {
        mStates.delete(assetId);
        await mPref.delete(assetId);
        await mPref.flush();
        MCLogger.info(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${assetId}] Evicted state and cleared preferences.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${assetId}] Failed to evict state: ${error.message}. Stack trace: ${error.stack}`);
        throw error as Error;
      }
    }
    else {
      MCLogger.debug(MCLogModule.MCAssetStateRepository, () => `[AssetId: ${assetId}] No state found to evict.`);
    }
  }
}

export default MCAssetStateRepository;