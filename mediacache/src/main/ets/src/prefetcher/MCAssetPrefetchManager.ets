import { MCAssetCapabilityRegistry } from '../asset/MCAssetCapabilityRegistry';
import { MCAssetManager } from '../asset/MCAssetManager';
import { MCAssetProxyUtils } from '../asset/MCAssetProxyUtils';
import { MCAssetPrefetchOptions } from '../defines/MCAssetPrefetchOptions';
import { MCAbortController } from '../utils/MCAbortController';
import MCUtils from '../utils/MCUtils';
import { MCRequestScope } from '../utils/MCRequestScope';
import { MCAssetPrefetchUtils } from './MCAssetPrefetchUtils';

/** 预取门面；具体类型实现见 {@link MCAssetCapabilityRegistry.prefetchAsset}。 */
export namespace MCAssetPrefetchManager {
  export async function prefetch(resUrl: string, options?: MCAssetPrefetchOptions): Promise<void> {
    // 参数校验
    const prefetchSize = options?.prefetchSize;
    if ( prefetchSize !== undefined && prefetchSize <= 0 ) {
      throw new Error(`Invalid parameter with prefetchSize: ${prefetchSize}.`); // prefetchSize 无效, 必须大于0;
    }

    const prefetchSegmentCount = options?.prefetchSegmentCount;
    if ( prefetchSegmentCount !== undefined && prefetchSegmentCount <= 0 ) {
      throw new Error(`Invalid parameter with prefetchSegmentCount: ${prefetchSegmentCount}.`); // prefetchSegmentCount 无效, 必须大于0;
    }

    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    const proxyPath = await MCAssetProxyUtils.generateAssetProxyPath(resUrl);

    // 获取资产
    const asset = await MCAssetManager.getInstance().getAssetByProxyPath(proxyPath);
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    const prefetchAbortController = new MCAbortController();
    const prefetchAbortSignal = prefetchAbortController.signal;
    const prefetchOptions = MCUtils.setRecordValue(options, 'signal', prefetchAbortSignal) as MCAssetPrefetchOptions;

    signal?.addEventListener('aborted', (e) => prefetchAbortController.abort(e));

    try {
      // 持有引用期间禁止淘汰；类型分发由能力注册表统一处理
      await MCRequestScope.withAsset(asset, async () => {
        await MCAssetCapabilityRegistry.prefetchAsset(asset, proxyPath, prefetchOptions);
      });
    }
    catch (e) {
      prefetchAbortController.abort(e);
      throw e as Error;
    }
  }
}