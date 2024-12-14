import { HLSPlaylist, MCAssetUtils, MCUtils } from "../../../../../Index";
import { FILEAsset } from "../asset/filebased/FILEAsset";
import { HLSAsset } from "../asset/hls/HLSAsset";
import MCAssetProvider from "../asset/MCAssetProvider";
import HLSDefines from "../defines/HLSDefines";
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
     * 指定预缓存的文件数必须大于0.
     *
     * 对于普通媒体文件的预缓存, 因为只包含一个文件, 所以整个媒体文件将被缓存;
     * 对于流媒体(HLS)的预缓存, 会尝试预缓存的指定数量的段(ts)文件;
     * */
    prefetchFileCount?: number;

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

    /**
     * 预加载的进度回调;
     * */
    onProgress?: (progress: number) => void;
    additionalHeaders?: Record<string, string>;
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

    const requestTarget = await MCAssetUtils.generateProxyPath(resUrl);
    await prefetchByRequestTarget(requestTarget, options);
  }

  async function prefetchByRequestTarget(requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void> {
    const signal = options?.signal;
    checkAbortSignal(signal);

    // 获取资产
    const asset = await MCAssetProvider.getAssetBy(requestTarget);
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

    const mediaTotalLength = metadata.totalLength;
    if ( mediaTotalLength === 0 ) { // 空文件
      options?.onProgress?.(1);
      return;
    }

    // 分段请求数据
    if ( mediaTotalLength !== Number.MAX_SAFE_INTEGER && metadata.byteRangeAccessSupported ) {
      const prefetchSize = options?.prefetchSize === undefined ? mediaTotalLength : Math.min(options.prefetchSize, mediaTotalLength);
      const chunkSize = options?.chunkSize !== undefined && options?.chunkSize > 0 ? options.chunkSize : 5 * 1024 * 1024; // default: 5M;
      const concurrentPrefetchCount = getConcurrentPrefetchCount(options?.concurrentPrefetchCount); // default: 3;

      const fetchRequests: IMCDataRequest[] = [];
      const fetchProgresses: number[] = [];
      let offset = 0;
      while (offset < prefetchSize) {
        const rangeStart = offset;
        const rangeEnd = Math.min(offset + chunkSize, mediaTotalLength) - 1;
        const headers = MCUtils.modifyRecord(options?.additionalHeaders ?? { }, 'range', `bytes=${rangeStart}-${rangeEnd}`);
        const request: IMCDataRequest = {
          requestTarget: requestTarget,
          headers: headers,
        }
        fetchRequests.push(request);
        fetchProgresses.push(0);
        offset += chunkSize;
      }

      const fetchAbortController = new MCAbortController();
      const signalAbortedCallback = (error: Error) => fetchAbortController.abort(error); // 外部终止时, 内部停止预缓存;
      signal?.addEventListener('aborted', signalAbortedCallback);
      try {
        // 并发控制
        let requestIndex = 0;
        while (requestIndex < fetchRequests.length) {
          const promises: Promise<void>[] = [];
          for (let p = 0; p < concurrentPrefetchCount; p++) {
            const fetchIndex = requestIndex;
            const fetchProgressCallback = (receivedLength: number, expectedLength: number) => {
              fetchProgresses[fetchIndex] = receivedLength / expectedLength;
              options?.onProgress?.(fetchProgresses.reduce((prev, cur) => prev + cur, 0) / fetchProgresses.length);
            };
            const fetchRequest = fetchRequests[fetchIndex];
            promises.push(fetch(generatePrefetchId(), media, fetchRequest, fetchProgressCallback, fetchAbortController.signal)); // 传递 fetchAbortController.signal, 当外部终止时, 内部也停止预缓存;
            requestIndex += 1;
            if ( requestIndex >= fetchRequests.length ) break;
          }
          await Promise.all(promises);
        }
      }
      catch (error) {
        fetchAbortController.abort(error);
        throw error as Error;
      }
      finally {
        signal?.removeEventListener('aborted', signalAbortedCallback);
      }
    }
    // 请求媒体所有数据
    else {
      const headers = options?.additionalHeaders;
      const request: IMCDataRequest = {
        requestTarget: requestTarget,
        headers: headers,
      }
      return fetch(generatePrefetchId(), media, request, (receivedLength: number, expectedLength: number) => options?.onProgress?.(receivedLength / expectedLength), signal);
    }
  }

  async function prefetchHLSAsset(asset: HLSAsset, requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void> {
    const signal = options?.signal;
    checkAbortSignal(signal)

    // 获取播放列表
    const playlistMedia = await asset.getMediaBy(requestTarget);
    checkAbortSignal(signal);

    const playlistRequest: IMCDataRequest = {
      requestTarget: requestTarget,
      headers: options?.additionalHeaders
    }
    const playlistRawData = await read(generatePrefetchId(), playlistMedia, playlistRequest, signal)
    checkAbortSignal(signal);

    const playlist = playlistRawData ? new HLSPlaylist(MCUtils.bufferToString(playlistRawData)) : undefined;
    if ( !playlist || !playlist.allItems || playlist.allItems.length === 0 ) { // 空文件
      options?.onProgress?.(1);
      return;
    }

    if ( options?.prefetchSize ) {
      return prefetchHLSAssetMediasBySpecifiedSize(asset, playlist, options.prefetchSize, options.onProgress, options.signal)
    }

    if ( options?.prefetchFileCount ) {
      return prefetchHLSAssetMediasBySpecifiedSegmentCount(asset, playlist, options.prefetchFileCount, options.concurrentPrefetchCount, options.onProgress, options.signal)
    }

    return prefetchHLSAssetAllMedias(asset, playlist, options?.concurrentPrefetchCount, options?.onProgress, options?.signal)
  }

  async function prefetchHLSAssetMediasBySpecifiedSize(asset: HLSAsset, playlist: HLSPlaylist, specifiedSize: number, onProgress?: (progress: number) => void, signal?: MCAbortSignal): Promise<void> {
    checkAbortSignal(signal);

    // 处理分段
    const segments = playlist.segments;
    if ( segments && segments.length > 0 ) {
      let fetchedLength = 0;
      const items = playlist.allItems!;
      let itemIndex = 0;
      while (itemIndex < items.length && fetchedLength < specifiedSize) {
        const item = items[itemIndex];
        let prevLen = 0;
        const fetchProgressCallback = (receivedLength: number, _: number) => {
          if ( item.itemType === HLSDefines.ItemType.SEGMENT ) {
            fetchedLength += receivedLength - prevLen;
            prevLen = receivedLength;

            if ( onProgress ) {
              const progress = fetchedLength / specifiedSize;
              onProgress(progress);
            }
          }
        };
        await prefetchMediaByHLSItem(asset, item, fetchProgressCallback, signal); // 一个一个缓存, 不并发请求(并发请求不好控制 specifiedSize);
        itemIndex += 1;
      }
      return;
    }

    const variantStream = playlist.variantStream;
    if ( !variantStream ) {
      onProgress?.(1);
      return;
    }

    // 处理变体流 + renditions
    const audioRendition = playlist.audioRendition;
    const videoRendition = playlist.videoRendition;
    const subtitlesRendition = playlist.subtitlesRendition;

    const items: HLSDefines.Item[] = [];
    items.push(variantStream);
    if ( audioRendition ) items.push(audioRendition);
    if ( videoRendition ) items.push(videoRendition);
    if ( subtitlesRendition ) items.push(subtitlesRendition);

    const fetchProgresses: number[] = items.map(() => 0);
    let itemIndex = 0;
    while (itemIndex < items.length) {
      const item = items[itemIndex];
      const uri = item.uri!
      const fetchIndex = itemIndex;
      const fetchProgressCallback = (progress: number) => {
        fetchProgresses[fetchIndex] = progress;
        onProgress?.(fetchProgresses.reduce((prev, cur) => prev + cur, 0) / fetchProgresses.length);
      };

      if (item !== subtitlesRendition) {
        await prefetchByRequestTarget(uri, {
          prefetchSize: specifiedSize,
          onProgress: fetchProgressCallback,
          signal: signal // 传递 fetchAbortController.signal, 当外部终止时, 内部也停止预缓存;
        })
      }
      else {
        await prefetchMediaByHLSItem(asset, item, (receivedLength: number, expectedLength: number) => { fetchProgressCallback(receivedLength / expectedLength) }, signal);
      }
      itemIndex += 1;
    }
  }

  async function prefetchHLSAssetMediasBySpecifiedSegmentCount(asset: HLSAsset, playlist: HLSPlaylist, specifiedSegmentCount: number, concurrentPrefetchCount?: number, onProgress?: (progress: number) => void, signal?: MCAbortSignal): Promise<void> {
    checkAbortSignal(signal);

    const segments = playlist.segments;
    // 处理分段
    if ( segments && segments.length > 0 ) {
      const lastSegment = segments[Math.min(specifiedSegmentCount - 1, segments.length - 1)];
      const lastItemIndex = playlist.allItems!.indexOf(lastSegment);
      const items = playlist.allItems!.slice(0, lastItemIndex + 1);
      return prefetchMediaByHLSItems(asset, items, concurrentPrefetchCount, onProgress);
    }

    const variantStream = playlist.variantStream;
    if ( !variantStream ) {
      onProgress?.(1);
      return;
    }

    // 处理变体流 + renditions
    const audioRendition = playlist.audioRendition;
    const videoRendition = playlist.videoRendition;
    const subtitlesRendition = playlist.subtitlesRendition;

    const items: HLSDefines.Item[] = [];
    items.push(variantStream);
    if ( audioRendition ) items.push(audioRendition);
    if ( videoRendition ) items.push(videoRendition);
    if ( subtitlesRendition ) items.push(subtitlesRendition);

    const fetchProgresses: number[] = items.map(() => 0);
    let itemIndex = 0;
    while (itemIndex < items.length) {
      const item = items[itemIndex];
      const uri = item.uri!
      const fetchIndex = itemIndex;
      const fetchProgressCallback = (progress: number) => {
        fetchProgresses[fetchIndex] = progress;
        onProgress?.(fetchProgresses.reduce((prev, cur) => prev + cur, 0) / fetchProgresses.length);
      };

      if ( item !== subtitlesRendition ) {
        await prefetchByRequestTarget(uri, {
          prefetchFileCount: specifiedSegmentCount,
          concurrentPrefetchCount: concurrentPrefetchCount,
          onProgress: fetchProgressCallback,
          signal: signal
        })
      }
      else {
        await prefetchMediaByHLSItem(asset, item, fetchProgressCallback, signal);
      }
      itemIndex += 1;
    }
  }

  function prefetchHLSAssetAllMedias(asset: HLSAsset, playlist: HLSPlaylist, concurrentPrefetchCount?: number, onProgress?: (progress: number) => void, signal?: MCAbortSignal): Promise<void> {
    return prefetchHLSAssetMediasBySpecifiedSegmentCount(asset, playlist, Number.MAX_SAFE_INTEGER, concurrentPrefetchCount, onProgress, signal);
  }

  async function prefetchMediaByHLSItems(asset: HLSAsset, items: HLSDefines.Item[], concurrentPrefetchCount?: number, onProgress?: (progress: number) => void, signal?: MCAbortSignal): Promise<void> {
    checkAbortSignal(signal);

    concurrentPrefetchCount = getConcurrentPrefetchCount(concurrentPrefetchCount); // default: 3;

    const fetchAbortController = new MCAbortController();
    const signalAbortedCallback = (error: Error) => fetchAbortController.abort(error); // 外部终止时, 内部停止预缓存;
    signal?.addEventListener('aborted', signalAbortedCallback);
    try {
      // 并发控制
      let itemIndex = 0;
      const fetchProgresses: number[] = items.map(() => 0);
      while (itemIndex < items.length) {
        const promises: Promise<void>[] = [];
        for (let p = 0; p < concurrentPrefetchCount; p++) {
          const fetchIndex = itemIndex;
          const fetchProgressCallback = (receivedLength: number, expectedLength: number) => {
            fetchProgresses[fetchIndex] = receivedLength / expectedLength;
            onProgress?.(fetchProgresses.reduce((prev, cur) => prev + cur, 0) / fetchProgresses.length);
          };

          const item = items[fetchIndex];
          promises.push(prefetchMediaByHLSItem(asset, item, fetchProgressCallback, fetchAbortController.signal)); // 传递 fetchAbortController.signal, 当外部终止时, 内部也停止预缓存;
          itemIndex += 1;
          if ( itemIndex >= items.length ) break;
        }
        await Promise.all(promises);
      }
    }
    catch (error) {
      fetchAbortController.abort(error);
      throw error as Error;
    }
    finally {
      signal?.removeEventListener('aborted', signalAbortedCallback);
    }
  }

  async function prefetchMediaByHLSItem(asset: HLSAsset, item: HLSDefines.Item, onProgress?: (receivedLength: number, expectedLength: number) => void, signal?: MCAbortSignal): Promise<void> {
    checkAbortSignal(signal);

    const uri = item.uri;
    if ( uri ) {
      const media = await asset.getMediaBy(uri);
      checkAbortSignal(signal);

      const request: IMCDataRequest = {
        requestTarget: uri
      };
      return fetch(generatePrefetchId(), media, request, onProgress, signal);
    }
  }

  function fetch(clientId: number, media: IMCMedia, request: IMCDataRequest, onProgress?: (receivedLength: number, expectedLength: number) => void, signal?: MCAbortSignal): Promise<void> {
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
          onProgress(receivedLength, contentLength);
        }
      });

      fetcher.on("dataEnd", (fetcher: IMCDataFetcher) => {
        if ( signal && signal.isAborted ) {
          return;
        }

        if ( onProgress && contentLength === undefined ) {
          onProgress(receivedLength, receivedLength);
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

  function read(clientId: number, media: IMCMedia, request: IMCDataRequest, signal?: MCAbortSignal): Promise<ArrayBuffer | undefined> {
    return new Promise(async (resolve, reject) => {
      if ( signal && signal.isAborted ) {
        reject(signal.reason!);  // reject
        return;
      }

      const fetcher = new MCMediaDataFetcher(clientId, media, request);
      let buffer: ArrayBuffer | undefined = undefined
      fetcher.on("dataReceive", (_: IMCDataFetcher, __: number, data: ArrayBuffer) => {
        if ( signal && signal.isAborted ) {
          return;
        }
        buffer = buffer ? MCUtils.mergeArrayBuffers(buffer, data) : data;
      });

      fetcher.on("dataEnd", (fetcher: IMCDataFetcher) => {
        if ( signal && signal.isAborted ) {
          return;
        }

        clearFetcherEvents(fetcher);
        resolve(buffer);
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

  function getConcurrentPrefetchCount(concurrentPrefetchCount?: number): number {
    return concurrentPrefetchCount ? concurrentPrefetchCount : 3; // default: 3;
  }
}

export default MCAssetPrefetcher;