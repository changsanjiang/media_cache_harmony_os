import { FILEAsset } from '../asset/filebased/FILEAsset';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { MCAssetPrefetchOptions } from '../defines/MCAssetPrefetchOptions';
import MCUtils from '../utils/MCUtils';
import { MCAssetPrefetcherUtils } from './MCAssetPrefetcherUtils';
import { MCMediaDataPrefetcher } from './MCMediaDataPrefetcher';

export interface IFILEAssetPrefetcehr {
  prefetch(asset: FILEAsset, requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void>;
}

export class FILEAssetPrefetcher implements IFILEAssetPrefetcehr {
  async prefetch(asset: FILEAsset, requestTarget: string, options?: MCAssetPrefetchOptions | undefined): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetcherUtils.checkAbortSignal(signal);

    // 获取媒体
    const media = await asset.getMediaBy(requestTarget);
    MCAssetPrefetcherUtils.checkAbortSignal(signal);

    // 探测元数据
    const probeRequest: IMCDataRequest = {
      requestTarget: requestTarget,
      headers: options?.additionalHeaders
    };
    const metadata = await media.probe(probeRequest, signal);
    const totalLength = metadata.totalLength;
    if ( totalLength === 0 ) { // 空文件
      options?.onProgress?.(1);
      return;
    }

    // 分段请求数据
    if ( totalLength != Number.MAX_SAFE_INTEGER && metadata.byteRangeAccessSupported ) {
      const prefetchSize = options?.prefetchSize === undefined ? totalLength : Math.min(options.prefetchSize, totalLength);
      const chunkSize = MCAssetPrefetcherUtils.getChunkSize(options);
      const concurrentPrefetchCount = MCAssetPrefetcherUtils.getConcurrentPrefetchCount(options);

      // 创建分段请求
      const allRequests: IMCDataRequest[] = [];
      const allProgresses: number[] = [];
      let reqOffset = 0;
      while (reqOffset < prefetchSize) {
        const rangeStart = reqOffset;
        const rangeEnd = Math.min(reqOffset + chunkSize, prefetchSize) - 1;
        const headers = MCUtils.modifyRecord(options?.additionalHeaders ?? { }, 'range', `bytes=${rangeStart}-${rangeEnd}`);
        const request: IMCDataRequest = {
          requestTarget: requestTarget,
          headers: headers,
        }
        allRequests.push(request);
        allProgresses.push(0);
        reqOffset += chunkSize;
      }

      // 分批预加载
      let reqIdx = 0;
      while ( reqIdx < allRequests.length ) {
        const batch = allRequests.slice(reqIdx, reqIdx + concurrentPrefetchCount);
        const fetches = batch.map((req, index) => {
          const prefetchId = MCAssetPrefetcherUtils.generatePrefetchId();
          const progressCallback = options?.onProgress ? (receivedLength: number, expectedLength: number) => {
            const fetchIdx = reqIdx + index;
            allProgresses[fetchIdx] = receivedLength / expectedLength;
            options.onProgress!(allProgresses.reduce((prev, cur) => prev + cur, 0) / allProgresses.length);
          } : undefined;
          const prefetcher = new MCMediaDataPrefetcher(
            prefetchId,
            media,
            req,
            progressCallback,
            signal
          );
          return prefetcher.prefetch();
        });
        await Promise.all(fetches);
        reqIdx += concurrentPrefetchCount;
      }
    }
    // 请求所有数据
    else {
      const headers = options?.additionalHeaders ? MCUtils.modifyRecord(options.additionalHeaders, 'range', undefined) : undefined;
      const request: IMCDataRequest = {
        requestTarget: requestTarget,
        headers: headers,
      };
      const prefetchId = MCAssetPrefetcherUtils.generatePrefetchId();
      const progressCallback = options?.onProgress ? (receivedLength: number, expectedLength: number) => options.onProgress!(receivedLength / expectedLength) : undefined;
      const prefecher = new MCMediaDataPrefetcher(
        prefetchId,
        media,
        request,
        progressCallback,
        signal
      );
      await prefecher.prefetch();
    }
  }
}