import { IMCAsset } from '../defines/IMCAsset';

/**
 * 在一次预取/导出等操作中配对 Asset 的 readwriteRetain / readwriteRelease。
 *
 * 与播放路径中 {@link MCMediaHttpSession} 内的 retain 规则一致，供 {@link MCCachePolicy} 判断 in-use。
 */
export class MCRequestScope {
  private mAsset: IMCAsset;
  private mReleased = false;

  /** 等价于一次 retain；须通过 release 或 withAsset 的 finally 释放。 */
  constructor(asset: IMCAsset) {
    this.mAsset = asset;
    asset.readwriteRetain();
  }

  /** 幂等：重复调用不会二次 release。 */
  release(): void {
    if ( !this.mReleased ) {
      this.mReleased = true;
      this.mAsset.readwriteRelease();
    }
  }

  /**
   * 在持有 Asset 引用期间执行异步任务，结束时必定 release。
   */
  static async withAsset<T>(asset: IMCAsset, work: () => Promise<T>): Promise<T> {
    const scope = new MCRequestScope(asset);
    try {
      return await work();
    }
    finally {
      scope.release();
    }
  }
}