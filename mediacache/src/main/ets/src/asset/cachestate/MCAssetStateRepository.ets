import { MCPreferences } from "../../utils/MCPreferences";
import MCUtils from "../../utils/MCUtils";
import { MCAssetState } from "./MCAssetState";

/** 记录资源状态; 例如是否固定; */
namespace MCAssetStateRepository {
  const mStates = new Map<string, MCAssetState>();
  const mPref = new MCPreferences<string>('mc_asset_state_pref');

  export async function prepare(): Promise<void> {
    let record = await mPref.getAll();
    const map = MCUtils.recordToMap(record);
    for ( let element of Array.from(map.entries()) ) {
      try {
        const assetId = element[0];
        const state = JSON.parse(element[1]) as MCAssetState;
        mStates.set(assetId, state);
      }
      catch (ignored) { }
    }
  }

  /** 判断资产是否被固定 */
  export function isPinned(assetId: string): boolean {
    return mStates.get(assetId)?.isPinned ?? false;
  }

  /** 设置资产的固定状态 */
  export async function setPinned(assetId: string, isPinned: boolean): Promise<void> {
    const state: MCAssetState = { isPinned: isPinned };
    mStates.set(assetId, state);
    await mPref.set(assetId, JSON.stringify(state));
    await mPref.flush();
  }

  export async function onEvict(assetId: string): Promise<void> {
    if ( mStates.get(assetId) ) {
      mStates.delete(assetId);
      await mPref.delete(assetId);
      await mPref.flush();
    }
  }
}

export default MCAssetStateRepository;