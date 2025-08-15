import { HLSAsset } from '../asset/hls/HLSAsset';
import { IMCAssetExporter } from '../defines/IMCAssetExporter';
import { MCAssetExportOptions } from '../defines/MCAssetExportOptions';
import { MCMediaKind } from '../defines/MCMediaKind';
import { MCAssetPrefetchUtils } from '../prefetcher/MCAssetPrefetchUtils';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCMedia } from '../defines/IMCMedia';
import { MCAbortSignal } from '../utils/MCAbortController';
import { HLSPlaylist } from '../asset/hls/HLSPlaylist';
import MCUtils from '../utils/MCUtils';
import { IMCMediaDataReader, MCMediaDataReader } from '../prefetcher/MCMediaDataReader';

export class HLSAssetExporter implements IMCAssetExporter<HLSAsset> {
  async export(asset: HLSAsset, requestTarget: string, targetDir: string, options?: MCAssetExportOptions): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 获取播放列表
    const media = await asset.getMediaBy(requestTarget);
    if ( media.mediaKind != MCMediaKind.PLAYLIST ) {
      throw new Error(`Export failed: expected mediaKind=PLAYLIST but got "${MCMediaKind[media.mediaKind]}". requestTarget="${requestTarget}`);
    }
    MCAssetPrefetchUtils.checkAbortSignal(signal);

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



    throw new Error("Method not implemented.");
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