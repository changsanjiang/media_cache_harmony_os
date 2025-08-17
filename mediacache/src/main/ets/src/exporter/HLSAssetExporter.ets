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
import { MCAssetExportInfo, MCMediaExportInfo } from './MCAssetExportInfo';
import { MCAssetExportUtils } from './MCAssetExportUtils';
import { MCCopyFileConflictStrategy } from '../defines/MCCopyFileConflictStrategy';
import { MCAssetType } from '../defines/MCAssetType';
import { MCMediaExportPath } from './MCMediaExportPath';

export class HLSAssetExporter implements IMCAssetExporter<HLSAsset> {
  async export(asset: HLSAsset, proxyPath: string, targetDir: string, options?: MCAssetExportOptions, ctx?: HLSAssetExportContext): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 获取播放列表
    const media = await asset.getMediaByProxyPath(proxyPath);
    if (media.mediaKind != MCMediaKind.PLAYLIST) {
      throw new Error(`Export failed: expected mediaKind=PLAYLIST but got "${MCMediaKind[media.mediaKind]}". proxyPath="${proxyPath}`);
    }
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // first: export playlist
    const mediaRequest: IMCDataRequest = {
      requestTarget: proxyPath,
      headers: options?.additionalHeaders,
    };

    const mediaExporter = new MCMediaExporter(
      media,
      mediaRequest,
      MCMediaExportPath.resolveMetadataDestPath(media.id, media.mediaKind, targetDir),
      MCMediaExportPath.resolveContentDestPath(media.id, media.mediaKind, targetDir),
      {
        conflictStrategy: options?.conflictStrategy,
        signal: options?.signal,
      }
    );
    await mediaExporter.export();

    // next: parse playlist
    const playlistRequest = mediaRequest;
    const playlistRawData = await this.readRawData(media, playlistRequest, signal);
    const playlist = playlistRawData ? new HLSPlaylist(MCUtils.bufferToString(playlistRawData)) : undefined;
    const allItems = playlist?.allItems;
    const playlistMediaId = media.id;
    if ( !ctx ) ctx = { medias: [] };
    ctx.medias.push({ mediaId: media.id, mediaKind: media.mediaKind });

    // 空文件、空列表
    if ( !playlist || !allItems || allItems.length == 0 ) {
      if ( playlistMediaId == asset.id ) await this.saveExportInfo(ctx, asset, targetDir, options?.conflictStrategy);
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
      const proxyPaths: string[] = Array.from(set);
      for (let i = 0; i < proxyPaths.length; ++i) {
        const proxyPath = proxyPaths[i];
        const media = await asset.getMediaByProxyPath(proxyPath);
        MCAssetPrefetchUtils.checkAbortSignal(signal);
        const mediaRequest: IMCDataRequest = {
          requestTarget: proxyPath,
          headers: options?.additionalHeaders,
        };
        const mediaExporter = new MCMediaExporter(
          media,
          mediaRequest,
          MCMediaExportPath.resolveMetadataDestPath(media.id, media.mediaKind, targetDir),
          MCMediaExportPath.resolveContentDestPath(media.id, media.mediaKind, targetDir),
          {
            conflictStrategy: options?.conflictStrategy,
            onProgress: options?.onProgress ? (progress) => {
              options.onProgress!((i + progress) / proxyPaths.length);
            } : undefined,
            signal: options?.signal
          }
        );
        await mediaExporter.export();
        ctx.medias.push({ mediaId: media.id, mediaKind: media.mediaKind });
      }
      if ( playlistMediaId == asset.id ) await this.saveExportInfo(ctx, asset, targetDir, options?.conflictStrategy);
      return;
    }

    // 否则导出变体流
    const variantStream = playlist.variantStream;
    if (!variantStream) {
      if ( playlistMediaId == asset.id ) await this.saveExportInfo(ctx, asset, targetDir, options?.conflictStrategy);
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
      const proxyPath = subtitlesRendition.uri!;
      const media = await asset.getMediaByProxyPath(proxyPath);
      MCAssetPrefetchUtils.checkAbortSignal(signal);
      const mediaRequest: IMCDataRequest = {
        requestTarget: proxyPath,
        headers: options?.additionalHeaders,
      };
      const mediaExporter = new MCMediaExporter(
        media,
        mediaRequest,
        MCMediaExportPath.resolveMetadataDestPath(media.id, media.mediaKind, targetDir),
        MCMediaExportPath.resolveContentDestPath(media.id, media.mediaKind, targetDir),
        {
          conflictStrategy: options?.conflictStrategy,
          signal: options?.signal
        }
      );
      await mediaExporter.export();
      ctx.medias.push({ mediaId: media.id, mediaKind: media.mediaKind });
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
        },
        ctx,
      );
    }
    if ( playlistMediaId == asset.id ) await this.saveExportInfo(ctx, asset, targetDir, options?.conflictStrategy);
  }

  private saveExportInfo(ctx: HLSAssetExportContext, asset: HLSAsset, targetDir: string, conflictStrategy?: MCCopyFileConflictStrategy): Promise<void> {
    const exportInfo: MCAssetExportInfo = {
      assetId: asset.id,
      assetType: MCAssetType.HLS,
      medias: ctx.medias,
    };
    return MCAssetExportUtils.saveExportInfo(exportInfo, targetDir, conflictStrategy);
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

interface HLSAssetExportContext {
  readonly medias: MCMediaExportInfo[]; // 记录已导出的媒体;
}