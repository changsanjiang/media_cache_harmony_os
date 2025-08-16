import { FILEAsset } from '../asset/filebased/FILEAsset';
import { HLSAsset } from '../asset/hls/HLSAsset';
import { MCAssetManager } from '../asset/MCAssetManager';
import MCAssetUtils from '../asset/MCAssetUtils';
import { MCAssetPrefetchOptions } from '../defines/MCAssetPrefetchOptions';
import { MCAssetType } from '../defines/MCAssetType';
import { FILEAssetPrefetcher } from './FILEAssetPrefetcher';
import { HLSAssetPrefetcher } from './HLSAssetPrefetcher';
import { MCAssetPrefetchUtils } from './MCAssetPrefetchUtils';

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

    const proxyPath = await MCAssetUtils.generateProxyPath(resUrl);

    // 获取资产
    const asset = await MCAssetManager.getInstance().getAssetByProxyPath(proxyPath);
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 根据资产类型进行预加载
    try {
      asset.readwriteRetain();
      switch (asset.type) {
        case MCAssetType.FILE_BASED: {
          const prefetcher = new FILEAssetPrefetcher();
          await prefetcher.prefetch(asset as FILEAsset, proxyPath, options);
          break;
        }
        case MCAssetType.HLS: {
          const prefetcher = new HLSAssetPrefetcher();
          await prefetcher.prefetch(asset as HLSAsset, proxyPath, options);
          break;
        }
        default:
          throw new Error(`Unsupported type: ${asset.type}`);
      }
    }
    finally {
      asset.readwriteRelease();
    }
  }
}