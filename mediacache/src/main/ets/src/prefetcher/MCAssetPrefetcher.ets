import { FILEAsset } from '../asset/filebased/FILEAsset';
import { HLSAsset } from '../asset/hls/HLSAsset';
import { HLSPlaylist } from '../asset/hls/HLSPlaylist';
import { MCAssetManager } from '../asset/MCAssetManager';
import MCAssetUtils from '../asset/MCAssetUtils';
import HLSDefines from '../defines/HLSDefines';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCMedia } from '../defines/IMCMedia';
import { MCAssetPrefetchOptions } from '../defines/MCAssetPrefetchOptions';
import { MCAssetType } from '../defines/MCAssetType';
import { MCAbortController, MCAbortSignal } from '../utils/MCAbortController';
import MCUtils from '../utils/MCUtils';
import { FILEAssetPrefetcher } from './FILEAssetPrefetcher';
import { HLSAssetPrefetcher } from './HLSAssetPrefetcher';
import { MCAssetPrefetcherUtils } from './MCAssetPrefetcherUtils';
import { IMCMediaDataPrefetcher, MCMediaDataPrefetcher } from './MCMediaDataPrefetcher';
import { IMCMediaDataReader, MCMediaDataReader } from './MCMediaDataReader';

export namespace MCAssetPrefetcher {
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
    MCAssetPrefetcherUtils.checkAbortSignal(signal);

    const requestTarget = await MCAssetUtils.generateProxyPath(resUrl);
    await prefetchByRequestTarget(requestTarget, options);
  }

  async function prefetchByRequestTarget(requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetcherUtils.checkAbortSignal(signal);

    // 获取资产
    const asset = await MCAssetManager.getInstance().getAssetByRequestTarget(requestTarget);
    MCAssetPrefetcherUtils.checkAbortSignal(signal);

    // 根据资产类型进行预加载
    try {
      asset.readwriteRetain();
      switch (asset.type) {
        case MCAssetType.FILE_BASED:
          await prefetchFILEAsset(asset as FILEAsset, requestTarget, options);
          break;
        case MCAssetType.HLS:
          await prefetchHLSAsset(asset as HLSAsset, requestTarget, options);
          break;
        default:
          throw new Error(`Unsupported type: ${asset.type}`);
      }
    }
    finally {
      asset.readwriteRelease();
    }
  }

  async function prefetchFILEAsset(asset: FILEAsset, requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void> {
    const prefetcher = new FILEAssetPrefetcher();
    return prefetcher.prefetch(asset, requestTarget, options);
  }

  async function prefetchHLSAsset(asset: HLSAsset, requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void> {
    const prefetcher = new HLSAssetPrefetcher();
    return prefetcher.prefetch(asset, requestTarget, options);
  }
}