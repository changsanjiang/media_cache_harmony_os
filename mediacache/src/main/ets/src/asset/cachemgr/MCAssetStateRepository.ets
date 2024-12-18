import { MCUtils } from "../../../../../../Index";
import { MCPreferences } from "../../utils/MCPreferences";
import { MCAssetState } from "./MCAssetState";

namespace MCAssetStateRepository {
  const mStates = new Map<string, MCAssetState>();
  const mPref = new MCPreferences<string>('mc_asset_state_pref');

  export async function prepare(): Promise<void> {
    let record = await mPref.getAll();
    const map = MCUtils.recordToMap(record);
    for ( let element of Array.from(map.entries()) ) {
      const assetId = element[0];
      if ( mStates.get(assetId) ) {
        const state = JSON.parse(element[1]) as MCAssetState;
        mStates.set(assetId, state);
      }
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
}

export default MCAssetStateRepository;