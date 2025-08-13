import { HLSAsset } from '../asset/hls/HLSAsset';
import { HLSPlaylist } from '../asset/hls/HLSPlaylist';
import HLSDefines from '../defines/HLSDefines';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCMedia } from '../defines/IMCMedia';
import { MCAssetPrefetchOptions } from '../defines/MCAssetPrefetchOptions';
import { MCMediaKind } from '../defines/MCMediaKind';
import { MCAbortSignal } from '../utils/MCAbortController';
import MCUtils from '../utils/MCUtils';
import { MCAssetPrefetcherUtils } from './MCAssetPrefetcherUtils';
import { MCMediaDataPrefetcher } from './MCMediaDataPrefetcher';
import { IMCMediaDataReader, MCMediaDataReader } from './MCMediaDataReader';

export interface IHLSAssetPrefetcher {
  prefetch(asset: HLSAsset, requestTarget: string, options?: MCAssetPrefetchOptions): Promise<void>;
}

export class HLSAssetPrefetcher implements IHLSAssetPrefetcher {
  async prefetch(asset: HLSAsset, requestTarget: string, options?: MCAssetPrefetchOptions | undefined): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetcherUtils.checkAbortSignal(signal);

    // 获取播放列表
    const media = await asset.getMediaBy(requestTarget);
    if ( media.mediaKind != MCMediaKind.PLAYLIST ) {
      throw new Error(`Prefetch failed: expected mediaKind=PLAYLIST but got "${MCMediaKind[media.mediaKind]}". requestTarget="${requestTarget}`);
    }
    MCAssetPrefetcherUtils.checkAbortSignal(signal);

    // 获取播放列表数据
    const playlistRequest: IMCDataRequest = {
      requestTarget: requestTarget,
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
      const concurrentPrefetchCount = MCAssetPrefetcherUtils.getConcurrentPrefetchCount(options);
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
    if ( segments && segments.length > 0 ) {
      let fetchedLength = 0;
      const items = playlist.allItems!;
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

      // variant stream or audio video renditions
      if (item !== subtitlesRendition) {
        await this.prefetch(
          asset,
          uri,
          {
            prefetchSize: specifiedSize,
            onProgress: fetchProgressCallback,
            additionalHeaders: additionalHeaders,
            signal: signal,
          },
        );
      }
      // subtitles rendition
      else {
        await this.prefetchItem(
          asset,
          item,
          additionalHeaders,
          (receivedLength: number, expectedLength: number) => {
            fetchProgressCallback(receivedLength / expectedLength);
          },
          signal
        );
      }
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

      // variant stream or audio video renditions
      if ( item !== subtitlesRendition ) {
        await this.prefetch(
          asset,
          uri,
          {
            prefetchSegmentCount: specifiedSegmentCount,
            concurrentPrefetchCount: concurrentPrefetchCount,
            onProgress: fetchProgressCallback,
            additionalHeaders: additionalHeaders,
            signal: signal
          }
        );
      }
      // subtitles rendition
      else {
        await this.prefetchItem(
          asset,
          item,
          additionalHeaders,
          fetchProgressCallback,
          signal
        );
      }
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
    const uri = item.uri;
    if ( uri ) {
      const media = await asset.getMediaBy(uri);
      MCAssetPrefetcherUtils.checkAbortSignal(signal);

      const request: IMCDataRequest = {
        requestTarget: uri,
        headers: additionalHeaders
      };

      const prefetcher = new MCMediaDataPrefetcher(MCAssetPrefetcherUtils.generatePrefetchId(), media, request, onProgress, signal);
      await prefetcher.prefetch();
    }
  }

  private readRawData(
    media: IMCMedia,
    request: IMCDataRequest,
    signal?: MCAbortSignal
  ): Promise<ArrayBuffer | undefined> {
    const reader: IMCMediaDataReader = new MCMediaDataReader(MCAssetPrefetcherUtils.generatePrefetchId(), media, request, signal);
    return reader.read();
  }
}