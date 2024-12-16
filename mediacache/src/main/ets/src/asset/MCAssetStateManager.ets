import { MCUtils } from "../../../../../Index";
import { MCPreferences } from "../utils/MCPreferences";
import { MCRetryPromise } from "../utils/MCRetryPromise";

namespace MCAssetStateManager {
  interface AssetState {
    /** 标记资产是否"固定"在缓存中, 即使超出限制也不被删除; */
    isPinned: boolean;
  }

  const mStates = new Map<string, AssetState>();
  const mPref = new MCPreferences<string>('mc_asset_state_pref');
  let mPreparationPromise: Promise<void> | undefined = undefined;

  export async function prepare(): Promise<void> {
    if ( !mPreparationPromise ) {
      mPreparationPromise = new MCRetryPromise(async (resolve, reject) => {
        try {
          const record = await mPref.getAll();
          const map = MCUtils.recordToMap(record);
          for ( let element of Array.from(map.entries()) ) {
            const assetId = element[0];
            if ( mStates.get(assetId) ) {
              const state = JSON.parse(element[1]) as AssetState;
              mStates.set(assetId, state);
            }
          }
          resolve();
        }
        catch (error) {
          reject(error);
        }
      });
    }
    return mPreparationPromise;
  }

  /** 判断资产是否被固定 */
  export function isPinned(assetId: string): boolean {
    return mStates.get(assetId)?.isPinned ?? false;
  }

  /** 设置资产的固定状态 */
  export async function setPinned(assetId: string, isPinned: boolean): Promise<void> {
    const state: AssetState = { isPinned: isPinned };
    mStates.set(assetId, state);
    await mPref.set(assetId, JSON.stringify(state));
    await mPref.flush();
  }
}

export default MCAssetStateManager;