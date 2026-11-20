import { MCAssetManager } from '../MCAssetManager';
import MCAssetStateRepository from '../cachestate/MCAssetStateRepository';

/**
 * 缓存淘汰门禁：与 pin、内存中 readwrite 引用协作。
 *
 * @note 须在 {@link MCAssetCacheManager} 的 `evictAssets` 中统一过滤，避免播放中被删盘。
 */
export namespace MCCachePolicy {
  /**
   * 是否允许本轮淘汰该 assetId。
   *
   * - 已 pin：否
   * - 内存 Asset 实例 {@link IMCAsset.readwriteCount} &gt; 0（播放/预取/导出进行中）：否
   */
  export function canEvict(assetId: string): boolean {
    if ( MCAssetStateRepository.isPinned(assetId) ) {
      return false;
    }
    if ( MCAssetManager.getInstance().isAssetInUse(assetId) ) {
      return false;
    }
    return true;
  }
}