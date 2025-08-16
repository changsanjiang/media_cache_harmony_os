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
import { MCMediaExporter } from './MCMediaExporter';
import HLSDefines from '../defines/HLSDefines';

export class HLSAssetExporter implements IMCAssetExporter<HLSAsset> {
  async export(asset: HLSAsset, requestTarget: string, targetDir: string, options?: MCAssetExportOptions): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 获取播放列表
    const media = await asset.getMediaBy(requestTarget);
    if (media.mediaKind != MCMediaKind.PLAYLIST) {
      throw new Error(`Export failed: expected mediaKind=PLAYLIST but got "${MCMediaKind[media.mediaKind]}". requestTarget="${requestTarget}`);
    }
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // first: export playlist
    const mediaRequest: IMCDataRequest = {
      requestTarget: requestTarget,
      headers: options?.additionalHeaders,
    };
    const mediaExporter = new MCMediaExporter(media, mediaRequest, targetDir, {
      conflictStrategy: options?.conflictStrategy,
      signal: options?.signal,
    });
    await mediaExporter.export();

    // next: parse playlist
    const playlistRequest: IMCDataRequest = {
      requestTarget: requestTarget,
      headers: options?.additionalHeaders
    }
    const playlistRawData = await this.readRawData(media, playlistRequest, signal);
    const playlist = playlistRawData ? new HLSPlaylist(MCUtils.bufferToString(playlistRawData)) : undefined;
    const allItems = playlist?.allItems;
    // 空文件、空列表
    if (!playlist || !allItems || allItems.length == 0) {
      options?.onProgress?.(1.0);
      return;
    }

    // 如果存在ts片段, 就导出所有项目(keys、ts等)
    const segments = playlist.segments;
    if (segments && segments.length > 0) {
      const set: Set<string> = new Set();
      for (let item of allItems) {
        if (item.uri) set.add(item.uri);
      }

      // export targets
      const requestTargets: string[] = Array.from(set);
      for (let i = 0; i < requestTargets.length; ++i) {
        const requestTarget = requestTargets[i];
        const media = await asset.getMediaBy(requestTarget);
        MCAssetPrefetchUtils.checkAbortSignal(signal);
        const mediaRequest: IMCDataRequest = {
          requestTarget: requestTarget,
          headers: options?.additionalHeaders,
        };
        const mediaExporter = new MCMediaExporter(media, mediaRequest, targetDir, {
          conflictStrategy: options?.conflictStrategy,
          onProgress: options?.onProgress ? (progress) => {
            options.onProgress!((i + progress) / requestTargets.length);
          } : undefined,
          signal: options?.signal
        });
        await mediaExporter.export();
      }
      return;
    }

    // 否则导出变体流
    const variantStream = playlist.variantStream;
    if (!variantStream) {
      options?.onProgress?.(1.0);
      return;
    }

    // 处理变体流 + renditions
    const audioRendition = playlist.audioRendition;
    const videoRendition = playlist.videoRendition;
    const subtitlesRendition = playlist.subtitlesRendition;

    // 先导出小文件
    // export subtitles
    if (subtitlesRendition) {
      const requestTarget = subtitlesRendition.uri!;
      const media = await asset.getMediaBy(requestTarget);
      MCAssetPrefetchUtils.checkAbortSignal(signal);
      const mediaRequest: IMCDataRequest = {
        requestTarget: requestTarget,
        headers: options?.additionalHeaders,
      };
      const mediaExporter = new MCMediaExporter(media, mediaRequest, targetDir, {
        conflictStrategy: options?.conflictStrategy,
        signal: options?.signal
      });
      await mediaExporter.export();
    }

    // export variant stream & audio video renditions
    const items: HLSDefines.Item[] = [];
    items.push(variantStream);
    if (audioRendition) items.push(audioRendition);
    if (videoRendition) items.push(videoRendition);
    for (let i = 0; i < items.length; ++i) {
      const item = items[i];
      await this.export(
        asset,
        item.uri!,
        targetDir,
        {
          conflictStrategy: options?.conflictStrategy,
          additionalHeaders: options?.additionalHeaders,
          onProgress: options?.onProgress ? (progress) => options.onProgress!((i + progress) / items.length) :
            undefined,
          signal: options?.signal,
        }
      );
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