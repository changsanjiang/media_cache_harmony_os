import { HLSAsset } from '../asset/hls/HLSAsset';
import { HLSPlaylist } from '../asset/hls/HLSPlaylist';
import HLSDefines from '../defines/HLSDefines';
import { IMCAssetPrefetcher } from '../defines/IMCAssetPrefetcher';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { toRequestRange } from '../defines/IMCHttpRequestRange';
import { IMCMedia } from '../defines/IMCMedia';
import { MCAssetPrefetchOptions } from '../defines/MCAssetPrefetchOptions';
import { MCMediaKind } from '../defines/MCMediaKind';
import { MCAbortSignal } from '../utils/MCAbortController';
import { MCRange } from '../utils/MCRange';
import MCUtils from '../utils/MCUtils';
import { MCAssetPrefetchUtils } from './MCAssetPrefetchUtils';
import { MCMediaDataPrefetcher } from './MCMediaDataPrefetcher';
import { IMCMediaDataReader, MCMediaDataReader } from './MCMediaDataReader';

export class HLSAssetPrefetcher implements IMCAssetPrefetcher<HLSAsset> {
  async prefetch(asset: HLSAsset, proxyPath: string, options?: MCAssetPrefetchOptions | undefined): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 获取播放列表
    const media = await asset.getMediaByProxyPath(proxyPath);
    if ( media.mediaKind != MCMediaKind.PLAYLIST ) {
      throw new Error(`Prefetch failed: expected mediaKind=PLAYLIST but got "${MCMediaKind[media.mediaKind]}". proxyPath="${proxyPath}`);
    }
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 获取播放列表数据
    const playlistRequest: IMCDataRequest = {
      requestTarget: proxyPath,
      headers: options?.additionalHeaders
    }
    const playlistRawData = await this.readRawData(media, playlistRequest, signal);
    const playlist = playlistRawData ? new HLSPlaylist(MCUtils.bufferToString(playlistRawData)) : undefined;
    if ( !playlist || !playlist.allItems || playlist.allItems.length == 0 ) { // 空文件、空列表
      options?.onProgress?.(1.0);
      return;
    }

    // 预加载指定大小的数据
    if ( options?.prefetchSize ) {
      await this.prefetchBySpecifiedSize(
        asset,
        playlist,
        options.prefetchSize,
        options?.additionalHeaders,
        options?.onProgress, signal
      );
    }
    // 预加载指定数量的片段或全部
    else {
      const prefetchSegmentCount = options?.prefetchSegmentCount ?? Number.MAX_SAFE_INTEGER;
      const concurrentPrefetchCount = MCAssetPrefetchUtils.getConcurrentPrefetchCount(options);
      await this.prefetchBySpecifiedSegmentCount(
        asset,
        playlist,
        prefetchSegmentCount,
        concurrentPrefetchCount,
        options?.additionalHeaders,
        options?.onProgress,
        signal
      );
    }
  }

  private async prefetchBySpecifiedSize(
    asset: HLSAsset,
    playlist: HLSPlaylist,
    specifiedSize: number,
    additionalHeaders?: Record<string, string>,
    onProgress?: (progress: number) => void,
    signal?: MCAbortSignal
  ): Promise<void> {
    // 处理分段
    const segments = playlist.segments;
    if ( playlist.allItems && segments && segments.length > 0 ) {
      let fetchedLength = 0;
      const items = playlist.allItems;
      let itemIndex = 0;
      while (itemIndex < items.length && fetchedLength < specifiedSize) {
        const item = items[itemIndex];
        let prevLen = 0;
        const progressCallback = (receivedLength: number, _: number) => {
          if ( item.itemType === HLSDefines.ItemType.SEGMENT ) {
            fetchedLength += receivedLength - prevLen;
            prevLen = receivedLength;
            onProgress?.(fetchedLength / specifiedSize);
          }
        };
        await this.prefetchItem(asset, item, additionalHeaders, progressCallback, signal); // 一个一个缓存, 不并发请求(并发请求时无法控制 specifiedSize);
        itemIndex += 1;
      }
      return;
    }

    const variantStream = playlist.variantStream;
    if ( !variantStream ) {
      onProgress?.(1.0);
      return;
    }

    // 处理变体流 + renditions
    const audioRendition = playlist.audioRendition;
    const videoRendition = playlist.videoRendition;
    const subtitlesRendition = playlist.subtitlesRendition;

    // subtitles
    if ( subtitlesRendition ) {
      await this.prefetchItem(
        asset,
        subtitlesRendition,
        additionalHeaders,
        undefined,
        signal
      );
    }

    // variant stream or audio video renditions
    const items: HLSDefines.Item[] = [];
    items.push(variantStream);
    if ( audioRendition ) items.push(audioRendition);
    if ( videoRendition ) items.push(videoRendition);

    const fetchProgresses: number[] = items.map(() => 0);
    let itemIndex = 0;
    while (itemIndex < items.length) {
      const item = items[itemIndex];
      const proxyPath = item.uri!
      const fetchIndex = itemIndex;
      const fetchProgressCallback = (progress: number) => {
        fetchProgresses[fetchIndex] = progress;
        onProgress?.(fetchProgresses.reduce((prev, cur) => prev + cur, 0) / fetchProgresses.length);
      };

      await this.prefetch(
        asset,
        proxyPath,
        {
          prefetchSize: specifiedSize,
          onProgress: fetchProgressCallback,
          additionalHeaders: additionalHeaders,
          signal: signal,
        },
      );
      itemIndex += 1;
    }
  }

  private async prefetchBySpecifiedSegmentCount(
    asset: HLSAsset,
    playlist: HLSPlaylist,
    specifiedSegmentCount: number,
    concurrentPrefetchCount: number,
    additionalHeaders?: Record<string, string>,
    onProgress?: (progress: number) => void,
    signal?: MCAbortSignal
  ): Promise<void> {
    // 处理分段
    const allSegments = playlist.segments;
    if ( playlist.allItems && allSegments && allSegments.length > 0 ) {
      const lastSegment = allSegments[Math.min(specifiedSegmentCount - 1, allSegments.length - 1)];
      const lastItemIndex = playlist.allItems.indexOf(lastSegment);
      const items = playlist.allItems.slice(0, lastItemIndex + 1);
      return this.prefetchItems(asset, items, concurrentPrefetchCount, additionalHeaders, onProgress, signal);
    }

    const variantStream = playlist.variantStream;
    if ( !variantStream ) {
      onProgress?.(1.0);
      return;
    }

    // 处理变体流 + renditions
    const audioRendition = playlist.audioRendition;
    const videoRendition = playlist.videoRendition;
    const subtitlesRendition = playlist.subtitlesRendition;

    // prefetch subtitles
    if ( subtitlesRendition ) {
      await this.prefetchItem(
        asset,
        subtitlesRendition,
        additionalHeaders,
        undefined,
        signal
      );
    }

    // prefetch variant stream or audio video renditions
    const items: HLSDefines.Item[] = [];
    items.push(variantStream);
    if ( audioRendition ) items.push(audioRendition);
    if ( videoRendition ) items.push(videoRendition);

    const fetchProgresses: number[] = items.map(() => 0);
    let itemIndex = 0;
    while (itemIndex < items.length) {
      const item = items[itemIndex];
      const proxyPath = item.uri!
      const fetchIndex = itemIndex;
      const fetchProgressCallback = (progress: number) => {
        fetchProgresses[fetchIndex] = progress;
        onProgress?.(fetchProgresses.reduce((prev, cur) => prev + cur, 0) / fetchProgresses.length);
      };

      await this.prefetch(
        asset,
        proxyPath,
        {
          prefetchSegmentCount: specifiedSegmentCount,
          concurrentPrefetchCount: concurrentPrefetchCount,
          onProgress: fetchProgressCallback,
          additionalHeaders: additionalHeaders,
          signal: signal
        }
      );
      itemIndex += 1;
    }
  }

  private async prefetchItems(
    asset: HLSAsset,
    items: HLSDefines.Item[],
    concurrentPrefetchCount: number,
    additionalHeaders?: Record<string, string>,
    onProgress?: (progress: number) => void,
    signal?: MCAbortSignal
  ): Promise<void> {
    const fetchProgresses: number[] = items.map(() => 0);

    // 并发控制
    let itemIndex = 0;
    while ( itemIndex < items.length ) {
      const batch = items.slice(itemIndex, itemIndex + concurrentPrefetchCount);
      const fetches = batch.map((item, index) => this.prefetchItem(asset, item, additionalHeaders, (receivedLength: number, expectedLength: number) => {
        const fetchIndex = itemIndex + index;
        fetchProgresses[fetchIndex] = receivedLength / expectedLength;
        onProgress?.(fetchProgresses.reduce((prev, cur) => prev + cur, 0) / fetchProgresses.length);
      }, signal));
      await Promise.all(fetches);
      itemIndex += concurrentPrefetchCount;
    }
  }

  private async prefetchItem(
    asset: HLSAsset,
    item: HLSDefines.Item,
    additionalHeaders?: Record<string, string>,
    onProgress?: (receivedLength: number, expectedLength: number) => void,
    signal?: MCAbortSignal
  ): Promise<void> {
    const proxyPath = item.uri;
    if ( proxyPath ) {
      const media = await asset.getMediaByProxyPath(proxyPath);
      MCAssetPrefetchUtils.checkAbortSignal(signal);

      let headers = additionalHeaders;
      let byteRange: MCRange | undefined = undefined;
      switch(item.itemType) {
        case HLSDefines.ItemType.INITIALIZATION:
          byteRange = (item as HLSDefines.InitializationItem).byteRange;
          break;
        case HLSDefines.ItemType.SEGMENT:
          byteRange = (item as HLSDefines.SegmentItem).byteRange;
          break;
      }
      if ( byteRange ) {
        const reqRange = toRequestRange(byteRange);
        const reqRangeHeader = reqRange.toRangeHeader();
        headers = MCUtils.modifyRecord(headers ?? {}, 'range', reqRangeHeader);
      }

      const request: IMCDataRequest = {
        requestTarget: proxyPath,
        headers: headers
      };

      const prefetcher = new MCMediaDataPrefetcher(media, request, onProgress, signal);
      await prefetcher.prefetch();
    }
  }

  private readRawData(
    media: IMCMedia,
    request: IMCDataRequest,
    signal?: MCAbortSignal
  ): Promise<ArrayBuffer | undefined> {
    const reader: IMCMediaDataReader = new MCMediaDataReader(media, request, signal);
    return reader.read();
  }
}