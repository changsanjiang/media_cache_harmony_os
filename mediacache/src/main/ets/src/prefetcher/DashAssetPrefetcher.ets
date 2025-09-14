import { DashAsset } from "../asset/dash/DashAsset";
import { DashParser } from "../asset/dash/DashParser";
import { DashTrack } from "../defines/DashDefines";
import { IMCAssetPrefetcher } from "../defines/IMCAssetPrefetcher";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCMedia } from "../defines/IMCMedia";
import { MCAssetPrefetchOptions } from "../defines/MCAssetPrefetchOptions";
import { MCMediaKind } from "../defines/MCMediaKind";
import { MCAbortSignal } from "../utils/MCAbortController";
import MCUtils from "../utils/MCUtils";
import { MCAssetPrefetchUtils } from "./MCAssetPrefetchUtils";
import { IMCMediaDataReader, MCMediaDataReader } from "./MCMediaDataReader";

export class DashAssetPrefetcher implements IMCAssetPrefetcher<DashAsset> {
  async prefetch(asset: DashAsset, proxyPath: string, options?: MCAssetPrefetchOptions | undefined): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // mpd media
    const media = await asset.getMediaByProxyPath(proxyPath);
    if ( media.mediaKind != MCMediaKind.PLAYLIST ) {
      throw new Error(`Prefetch failed: expected mediaKind=PLAYLIST but got "${MCMediaKind[media.mediaKind]}". proxyPath="${proxyPath}`);
    }
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    const mpdRequest: IMCDataRequest = {
      requestTarget: proxyPath,
      headers: options?.additionalHeaders,
    };
    const mpdRawData = await this.readRawData(media, mpdRequest, signal);
    if ( !mpdRawData ) { // 空文件
      options?.onProgress?.(1.0);
      return;
    }

    const mpd = DashParser.parse(MCUtils.bufferToString(mpdRawData)).mpd;
    const tracks = DashParser.extractTracks(mpd);
    if ( tracks.length == 0 ) { // no segment
      options?.onProgress?.(1.0);
      return;
    }

    // 预加载指定大小的数据
    if ( options?.prefetchSize ) {
      await this.prefetchBySpecifiedSize(
        asset,
        tracks,
        options.prefetchSize,
        options?.additionalHeaders,
        options?.onProgress,
        signal
      )
      return
    }

    const prefetchSegmentCount = options?.prefetchSegmentCount ?? Number.MAX_SAFE_INTEGER;
    const concurrentPrefetchCount = MCAssetPrefetchUtils.getConcurrentPrefetchCount(options);
    await this.prefetchBySpecifiedSegmentCount(
      asset,
      tracks,
      prefetchSegmentCount,
      concurrentPrefetchCount,
      options?.additionalHeaders,
      options?.onProgress,
      signal,
    )
  }

  private async prefetchBySpecifiedSize(
    asset: DashAsset,
    tracks: DashTrack[],
    specifiedSize: number,
    additionalHeaders?: Record<string, string>,
    onProgress?: (progress: number) => void,
    signal?: MCAbortSignal
  ): Promise<void> {

  }

  private async prefetchBySpecifiedSegmentCount(
    asset: DashAsset,
    tracks: DashTrack[],
    specifiedSegmentCount: number,
    concurrentPrefetchCount: number,
    additionalHeaders?: Record<string, string>,
    onProgress?: (progress: number) => void,
    signal?: MCAbortSignal
  ): Promise<void> {

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