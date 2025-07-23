import { FILEAsset } from "../asset/filebased/FILEAsset";
import { HLSAsset } from "../asset/hls/HLSAsset";
import { HLSPlaylist } from "../asset/hls/HLSPlaylist";
import MCAssetManager from "../asset/MCAssetManager";
import MCAssetUtils from "../asset/MCAssetUtils";
import HLSDefines from "../defines/HLSDefines";
import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders } from "../defines/IMCHttpResponseHeaders";
import { IMCMedia } from "../defines/IMCMedia";
import { MCAssetPrefetchOptions } from "../defines/MCAssetPrefetchOptions";
import { MCAssetType } from "../defines/MCAssetType";
import { MCMediaDataFetcher } from "../media/MCMediaDataFetcher";
import { MCAbortController, MCAbortSignal } from "../utils/MCAbortController";
import MCUtils from "../utils/MCUtils";

export namespace MCAssetPrefetcher {
  let mPrefetchId = -1

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
    checkAbortSignal(signal);

    const requestTarget = await MCAssetUtils.generateProxyPath(resUrl);
    await prefetchByRequestTarget(requestTarget, options);
  }

  async function prefetchByRequestTarget(requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void> {
    const signal = options?.signal;
    checkAbortSignal(signal);

    // 获取资产
    const asset = await MCAssetManager.getAssetByRequestTarget(requestTarget);
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

    if ( options?.prefetchSegmentCount ) {
      return prefetchHLSAssetMediasBySpecifiedSegmentCount(asset, playlist, options.prefetchSegmentCount, options.concurrentPrefetchCount, options.onProgress, options.signal)
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
          prefetchSegmentCount: specifiedSegmentCount,
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
    return new Promise<void>((resolve, reject) => {
      const prefecher: IMCMediaDataPrefetcher = new MCMediaDataPrefetcher(clientId, media, request, onProgress, signal);
      prefecher.prefetch((e) => e == undefined ? resolve() : reject(e));
    });
  }

  function read(clientId: number, media: IMCMedia, request: IMCDataRequest, signal?: MCAbortSignal): Promise<ArrayBuffer | undefined> {
    return new Promise(async (resolve, reject) => {
      const reader: IMCMediaDataReader = new MCMediaDataReader(clientId, media, request, signal);
      reader.read((data, e) => e == undefined ? resolve(data) : reject(e));
    });
  }

  function checkAbortSignal(signal?: MCAbortSignal) {
    if ( signal && signal.isAborted ) {
      throw signal.reason!;
    }
  }

  function generatePrefetchId(): number {
    return --mPrefetchId
  }

  function getConcurrentPrefetchCount(concurrentPrefetchCount?: number): number {
    return concurrentPrefetchCount ? concurrentPrefetchCount : 3; // default: 3;
  }
}

interface IMCMediaDataPrefetcher {
  prefetch(complete: (error?: Error) => void): void;
}

class MCMediaDataPrefetcher implements IMCMediaDataPrefetcher {
  private mClientId: number;
  private mMedia: IMCMedia;
  private mRequest: IMCDataRequest;
  private mOnProgress?: (receivedLength: number, expectedLength: number) => void;
  private mSignal?: MCAbortSignal;

  private mDataFetcher?: IMCDataFetcher;
  private mSerialPromise = Promise.resolve();

  private mCompleted = false;
  private mOnComplete?: (error?: Error) => void = undefined;

  private mReceivedLength: number = 0;
  private mExpectedLength: number = 0;

  constructor(clientId: number, media: IMCMedia, request: IMCDataRequest, onProgress?: (receivedLength: number, expectedLength: number) => void, signal?: MCAbortSignal) {
    this.mClientId = clientId;
    this.mMedia = media;
    this.mRequest = request;
    this.mOnProgress = onProgress;
    this.mSignal = signal;
  }

  async prefetch(complete: (error?: Error) => void): Promise<void> {
   this.mOnComplete = complete;

   try {
     this.checkSignal();

     const fetcher = new MCMediaDataFetcher(this.mClientId, this.mMedia, this.mRequest);
     this.mDataFetcher = fetcher;

     fetcher.on("newDataReadable", (fetcher) => this.readData(fetcher));
     fetcher.on("aborted", (_, e) => this.onFetcherAborted(e));

     this.mSignal?.addEventListener("aborted", (e) => fetcher.abort(e));

     const responseHeaders = await fetcher.prepare();
     switch (responseHeaders.statusCode) {
       case 200:
         // mExpectedLength 不一定有值, 当数据以 chunked 形式响应时, 无法获取所请求的数据长度;
         this.mExpectedLength = (responseHeaders as IMCHttpOkResponseHeaders).contentLength ?? 0;
         break;
       case 206:
         this.mExpectedLength = (responseHeaders as IMCHttpPartialContentResponseHeaders).contentRange.length;
         break;
       default:
         throw new Error(`Invalid response with code: ${responseHeaders.statusCode}}`);
     }

     this.readData(fetcher);
   }
   catch (e) {
     this.onComplete(e);
   }
 }

  private readData(fetcher: IMCDataFetcher): void {
    this.enqueueTask(() => {
      if ( this.mCompleted ) {
        return;
      }

      const readableLength = fetcher.readableLength;
      if ( readableLength == 0 ) {
        return;
      }

      if ( fetcher.seek(fetcher.offset + readableLength) ) {
        this.mReceivedLength += readableLength;

        // mExpectedLength 不一定有值, 当数据以 chunked 形式响应时, 无法获取所请求的数据长度;
        if ( this.mExpectedLength > 0 ) {
          this.mOnProgress?.(this.mReceivedLength, this.mExpectedLength);
        }

        // 数据读取完毕
        if ( fetcher.isDataEnd ) {
          this.onComplete();
        }
      }
    });
  }

  private onFetcherAborted(e: Error): void {
    this.onComplete(e);
  }

  private onComplete(error?: Error): void {
    if ( this.mCompleted ) {
      return;
    }

    const fetcher = this.mDataFetcher;
    if ( fetcher ) {
      this.mDataFetcher = undefined;

      fetcher.off('newDataReadable');
      fetcher.off('aborted');

      if ( !fetcher.isCompleted ) {
        fetcher.abort(error);
      }
    }

    this.mCompleted = true;
    this.mOnComplete?.(error);
  }

  // 确保操作按顺序串行执行
  private enqueueTask(task: () => void | Promise<void>): void {
    this.mSerialPromise = this.mSerialPromise
      .catch((e: Error) => this.onComplete(e)) // 捕获上一个任务的异常，防止链断裂
      .then(async () => {
        if ( this.mCompleted ) {
          return;
        }
        return task(); // 执行新任务
      });
  }

  private checkSignal(): void {
    if ( this.mSignal && this.mSignal.isAborted ) {
      throw this.mSignal.reason!;
    }
  }
}

/** 注意数据读取量不能过大, 仅适合小文件; */
interface IMCMediaDataReader {
  read(complete: (data?: ArrayBuffer, error?: Error) => void): void;
}

class MCMediaDataReader implements IMCMediaDataReader {
  private mClientId: number;
  private mMedia: IMCMedia;
  private mRequest: IMCDataRequest;
  private mSignal?: MCAbortSignal;

  private mDataFetcher?: IMCDataFetcher = undefined;
  private mData?: ArrayBuffer = undefined;
  private mSerialPromise = Promise.resolve();

  private mCompleted = false;
  private mOnComplete?: (data?: ArrayBuffer, error?: Error) => void = undefined;

  constructor(clientId: number, media: IMCMedia, request: IMCDataRequest, signal?: MCAbortSignal) {
    this.mClientId = clientId;
    this.mMedia = media;
    this.mRequest = request;
    this.mSignal = signal;
  }

  async read(complete: (data?: ArrayBuffer, error?: Error) => void): Promise<void> {
    this.mOnComplete = complete;

    try {
      this.checkSignal();

      const fetcher: IMCDataFetcher = new MCMediaDataFetcher(this.mClientId, this.mMedia, this.mRequest);
      this.mDataFetcher = fetcher;

      fetcher.on("newDataReadable", (fetcher) => this.readData(fetcher));
      fetcher.on("aborted", (_, e) => this.onFetcherAborted(e));

      this.mSignal?.addEventListener("aborted", (e) => fetcher.abort(e));

      const responseHeaders = await fetcher.prepare();
      switch (responseHeaders.statusCode) {
        case 200: break;
        case 206: break;
        default:
          throw new Error(`Invalid response with code: ${responseHeaders.statusCode}}`);
      }
      this.readData(fetcher);
    }
    catch (e) {
      this.onComplete(e);
    }
  }

  private readData(fetcher: IMCDataFetcher): void {
    this.enqueueTask(async () => {
      if ( this.mCompleted ) {
        return;
      }

      const readableLength = fetcher.readableLength;
      if ( readableLength == 0 ) {
        return;
      }

      const data = await fetcher.read(readableLength);
      if ( data ) {
        this.mData = this.mData ? MCUtils.mergeArrayBuffers(this.mData, data) : data;

        if ( fetcher.isDataEnd ) {
          this.onComplete();
        }
      }
    });
  }

  private onFetcherAborted(e: Error): void {
    this.onComplete(e);
  }

  private onComplete(error?: Error): void {
    if ( this.mCompleted ) {
      return;
    }

    const fetcher = this.mDataFetcher;
    if ( fetcher ) {
      this.mDataFetcher = undefined;

      fetcher.off('newDataReadable');
      fetcher.off('aborted');

      if ( !fetcher.isCompleted ) {
        fetcher.abort(error);
      }
    }

    this.mCompleted = true;
    if ( error ) {
      this.mOnComplete?.(undefined, error);
    }
    else {
      this.mOnComplete?.(this.mData);
    }
  }

  // 确保操作按顺序串行执行
  private enqueueTask(task: () => void | Promise<void>): void {
    this.mSerialPromise = this.mSerialPromise
      .catch((e: Error) => this.onComplete(e)) // 捕获上一个任务的异常，防止链断裂
      .then(async () => {
        if ( this.mCompleted ) {
          return;
        }
        return task(); // 执行新任务
      });
  }

  private checkSignal(): void {
    if ( this.mSignal && this.mSignal.isAborted ) {
      throw this.mSignal.reason!;
    }
  }
}