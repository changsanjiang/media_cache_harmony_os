import { MCAssetUtils, MCUtils } from "../../../../../Index";
import { FILEAsset } from "../asset/filebased/FILEAsset";
import { HLSAsset } from "../asset/hls/HLSAsset";
import MCAssetManager from "../asset/MCAssetManager";
import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders } from "../defines/IMCHttpResponseHeaders";
import { IMCMedia } from "../defines/IMCMedia";
import { MCAssetType } from "../defines/MCAssetType";
import { MCMediaDataFetcher } from "../media/MCMediaDataFetcher";
import { MCAbortController, MCAbortSignal } from "../utils/MCAbortController";

namespace MCAssetPrefetcher {
  export interface MCAssetPrefetchOptions {

    // 如果 prefetchSize 和 prefetchFileCount 都未设置, 将会预缓存资产中的所有媒体;

    /**
     * 预缓存指定大小(bytes)的的数据;
     *
     * 对于普通媒体文件的预缓存, 除非文件本身小于设置的预取大小, 否则按设置的字节数预取;
     * 对于流媒体(HLS)的预缓存, 会尝试预缓存多个段(ts)文件, 直到下载的数据总大小大于等于设置的预取大小;
     * */
    prefetchSize?: number;

    /**
     * 预缓存指定数量的媒体文件; 这个参数主要用于流媒体(HLS), 因为它的播放列表(playlist)中通常包含多个段(ts)文件, 通过设置这个参数用来指定预缓存的文件数;
     *
     * 指定预缓存的文件数时必须大于0.
     *
     * 对于普通媒体文件的预缓存, 因为只包含一个文件, 所以整个媒体文件将被缓存;
     * 对于流媒体(HLS)的预缓存, 会尝试预缓存的指定数量的段(ts)文件;
     * */
    prefetchFileCount?: number;

    additionalHeaders?: Record<string, string>;

    /**
     * 指定分块大小; 预加载时可能会尝试分块请求媒体数据;
     *
     * 例如预加载 50M 的数据, 在预加载时会尝试将 50M 的数据按指定的 chunkSize 分成多个块进行预加载, 可以通过 concurrentPrefetchCount 设置预加载的并发数;
     *
     * 默认值是 5M;
     * */
    chunkSize?: number;

    /**
     * 设置分块预加载时的并发数;
     *
     * 默认值是 3;
     * */
    concurrentPrefetchCount?: number;

    onProgress?: (progress: number) => void;
    signal?: MCAbortSignal;
  }

  let mPrefetchId = -1

  export async function prefetch(resUrl: string, options?: MCAssetPrefetchOptions): Promise<void> {
    // 参数校验
    const prefetchSize = options?.prefetchSize;
    if ( prefetchSize !== undefined && prefetchSize <= 0 ) {
      throw new Error(`Invalid parameter with prefetchSize: ${prefetchSize}.`); // prefetchSize 无效, 必须大于0;
    }

    const prefetchFileCount = options?.prefetchFileCount;
    if ( prefetchFileCount !== undefined && prefetchFileCount <= 0 ) {
      throw new Error(`Invalid parameter with prefetchFileCount: ${prefetchFileCount}.`); // prefetchFileCount 无效, 必须大于0;
    }

    const signal = options?.signal;
    checkAbortSignal(signal);

    // 获取代理路径
    const requestTarget = await MCAssetUtils.generateProxyPath(resUrl);
    checkAbortSignal(signal);

    // 获取资产
    const asset = await MCAssetManager.getAssetBy(requestTarget);
    checkAbortSignal(signal);

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
    const signal = options?.signal;
    checkAbortSignal(signal);

    // 获取媒体
    const media = await asset.getMediaBy(requestTarget);
    checkAbortSignal(signal);

    // 探测媒体元数据
    const probeRequest: IMCDataRequest = {
      requestTarget: requestTarget,
      headers: options?.additionalHeaders
    };

    const metadata = await media.probe(probeRequest, signal);
    checkAbortSignal(signal);

    // 计算需要缓存的数据大小

    let prefetchSize = options?.prefetchSize;

    // 长度未知(Number.MAX_SAFE_INTEGER)或不支持范围请求时, 需要缓存所有数据, 需要设置为最大值;
    if ( prefetchSize === undefined || prefetchSize > metadata.totalLength || metadata.totalLength === Number.MAX_SAFE_INTEGER || metadata.byteRangeAccessSupported === false ) {
      prefetchSize = metadata.totalLength;
    }

    // 分段请求数据
    if ( metadata.totalLength !== Number.MAX_SAFE_INTEGER && metadata.byteRangeAccessSupported ) {
      const chunkSize = options?.chunkSize !== undefined && options?.chunkSize > 0 ? options.chunkSize : 5 * 1024 * 1024; // default: 5M;
      const concurrentPrefetchCount = options?.concurrentPrefetchCount !== undefined && options?.concurrentPrefetchCount > 0 ? options.concurrentPrefetchCount : 3; // default: 3;

      const requests: IMCDataRequest[] = [];
      const progresses: number[] = [];
      const totalLength = metadata.totalLength;
      let offset = 0;
      while (offset < prefetchSize) {
        const rangeStart = offset;
        const rangeEnd = Math.min(offset + chunkSize, totalLength) - 1;
        const headers = MCUtils.modifyRecord(options?.additionalHeaders ?? { }, 'range', `bytes=${rangeStart}-${rangeEnd}`);
        const request: IMCDataRequest = {
          requestTarget: requestTarget,
          headers: headers,
        }
        requests.push(request);
        progresses.push(0);
        offset += chunkSize;
      }

      // 并发控制
      let requestIndex = 0;
      while (requestIndex < requests.length) {
        const promises: Promise<void>[] = [];
        const fetchAbortController = new MCAbortController();
        const prefetchAbortedCallback = (error: Error) => fetchAbortController.abort(error);
        signal?.addEventListener('aborted', prefetchAbortedCallback);
        for (let p = 0; p < concurrentPrefetchCount; p++) {
          const fetchIndex = requestIndex;
          const onProgress: ((progress: number) => void) | undefined = options?.onProgress ? (progress) => {
            progresses[fetchIndex] = progress;
            options?.onProgress?.(progresses.reduce((prev, cur) => prev + cur, 0) / progresses.length);
          } : undefined;

          const request = requests[fetchIndex];
          promises.push(fetch(generatePrefetchId(), media, request, onProgress, fetchAbortController.signal));
          requestIndex += 1;
          if ( requestIndex >= requests.length ) break;
        }
        await Promise.all(promises).catch((error: Error) => {
          fetchAbortController.abort(error);
          return Promise.reject(error);
        }).finally(() => {
          signal?.removeEventListener('aborted', prefetchAbortedCallback);
        });
      }
    }
    // 请求媒体所有数据
    else {
      const headers = options?.additionalHeaders;
      const request: IMCDataRequest = {
        requestTarget: requestTarget,
        headers: headers,
      }
      return fetch(generatePrefetchId(), media, request, options?.onProgress, signal);
    }
  }

  async function prefetchHLSAsset(asset: HLSAsset, requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void> {
    const signal = options?.signal;
    if ( signal && signal.isAborted ) {
      throw signal.reason!;
    }
  }

  function fetch(clientId: number, media: IMCMedia, request: IMCDataRequest, onProgress?: (progress: number) => void, signal?: MCAbortSignal): Promise<void> {
    return new Promise(async (resolve, reject) => {
      if ( signal && signal.isAborted ) {
        reject(signal.reason!);  // reject
        return;
      }

      const fetcher = new MCMediaDataFetcher(clientId, media, request);

      let contentLength: number | undefined = undefined;
      fetcher.on('responseReceive', (fetcher: IMCDataFetcher, responseHeaders: IMCHttpResponseHeaders) => {
        if ( signal && signal.isAborted ) {
          return;
        }

        switch (responseHeaders.statusCode) {
          case 200:
            contentLength = (responseHeaders as IMCHttpOkResponseHeaders).contentLength;
            break;
          case 206:
            contentLength = (responseHeaders as IMCHttpPartialContentResponseHeaders).contentRange.length;
            break;
          default: {
            const error = new Error(`Invalid response with code: ${responseHeaders.statusCode}}`);
            fetcher.abort(error);
            break;
          }
        }
      });

      let receivedLength = 0;
      fetcher.on("dataReceive", (_: IMCDataFetcher, __: number, data: ArrayBuffer) => {
        if ( signal && signal.isAborted ) {
          return;
        }

        receivedLength += data.byteLength;
        if ( contentLength && onProgress ) { // contentLength 不一定有值, 当数据以 chunked 形式响应时, 无法获取所请求的数据长度;
          onProgress(receivedLength / contentLength);
        }
      });

      fetcher.on("dataEnd", (fetcher: IMCDataFetcher) => {
        if ( signal && signal.isAborted ) {
          return;
        }

        if ( onProgress && contentLength === undefined ) {
          onProgress(1);
        }

        clearFetcherEvents(fetcher);
        resolve();
      });

      fetcher.on("aborted", (fetcher: IMCDataFetcher, error: Error) => {
        if ( signal && signal.isAborted ) {
          return;
        }

        clearFetcherEvents(fetcher);
        reject(error); // reject
      });

      const signalAbortedCallback: ((error: Error) => void) | undefined = signal ? (error) => {
        clearFetcherEvents(fetcher);
        fetcher.abort(error);
        reject(error); // reject
      } : undefined;

      signal?.addEventListener('aborted', signalAbortedCallback!);

      try {
        // prepare
        await fetcher.prepare();
      }
      catch (error) {
        reject(error); // reject
      }
      finally {
        signal?.removeEventListener('aborted', signalAbortedCallback!);
      }
    });
  }

  function checkAbortSignal(signal?: MCAbortSignal) {
    if ( signal && signal.isAborted ) {
      throw signal.reason!;
    }
  }

  function clearFetcherEvents(fetcher: IMCDataFetcher) {
    fetcher.off('responseReceive');
    fetcher.off('dataReceive');
    fetcher.off('dataEnd');
    fetcher.off('aborted');
  }

  function generatePrefetchId(): number {
    return --mPrefetchId
  }
}

export default MCAssetPrefetcher;