import { FILEAsset } from '../asset/filebased/FILEAsset';
import { IMCAssetExporter } from '../defines/IMCAssetExporter';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { MCAssetExportOptions } from '../defines/MCAssetExportOptions';
import { MCAssetPrefetchUtils } from '../prefetcher/MCAssetPrefetchUtils';
import MCUtils from '../utils/MCUtils';
import { MCAssetExportInfo } from './MCAssetExportInfo';
import { MCAssetExportUtils } from './MCAssetExportUtils';
import { MCMediaExporter } from './MCMediaExporter';

export class FILEAssetExporter implements IMCAssetExporter<FILEAsset> {
  async export(asset: FILEAsset, proxyPath: string, targetDir: string, options?: MCAssetExportOptions): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // FILEAsset 只有一个媒体
    // 导出媒体
    const media = await asset.getMediaByProxyPath(proxyPath);
    MCAssetPrefetchUtils.checkAbortSignal(signal);
    const headers = options?.additionalHeaders ? MCUtils.modifyRecord(options.additionalHeaders, 'range', undefined) : undefined;
    const mediaRequest: IMCDataRequest = {
      requestTarget: proxyPath,
      headers: headers,
    };
    const mediaExporter = new MCMediaExporter(media, mediaRequest, targetDir, {
      conflictStrategy: options?.conflictStrategy,
      onProgress: options?.onProgress,
      signal: options?.signal
    });
    await mediaExporter.export();

    // 最后写入导出信息
    const exportInfo: MCAssetExportInfo = {
      assetId: asset.id
    };
    MCAssetExportUtils.saveExportInfo(exportInfo, targetDir, options?.conflictStrategy);
  }
}