import { FILEAsset } from "../asset/filebased/FILEAsset";
import { IMCAssetExporter } from "../defines/IMCAssetExporter";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { MCAssetExportOptions } from "../defines/MCAssetExportOptions";
import { MCAssetPrefetchUtils } from "../prefetcher/MCAssetPrefetchUtils";
import MCUtils from "../utils/MCUtils";
import { MCMediaExporter } from "./MCMediaExporter";

export class FILEAssetExporter implements IMCAssetExporter<FILEAsset> {
  async export(asset: FILEAsset, requestTarget: string, targetDir: string, options?: MCAssetExportOptions): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    const media = await asset.getMediaBy(requestTarget);
    if ( media.metadataReady && media.totalLength == 0 ) { // 空文件
      options?.onProgress?.(1.0);
      return;
    }

    const headers = options?.additionalHeaders ? MCUtils.modifyRecord(options.additionalHeaders, 'range', undefined) : undefined;
    const mediaRequest: IMCDataRequest = {
      requestTarget: requestTarget,
      headers: headers,
    };
    const mediaExporter = new MCMediaExporter(media, mediaRequest, targetDir, {
      conflictStrategy: options?.conflictStrategy,
      onProgress: options?.onProgress,
      signal: options?.signal
    });
    return mediaExporter.export();
  }
}