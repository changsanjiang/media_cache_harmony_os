import { FILEAsset } from "../asset/filebased/FILEAsset";
import { IMCAssetExporter } from "../defines/IMCAssetExporter";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { MCAssetExportOptions } from "../defines/MCAssetExportOptions";
import { MCAssetPrefetchUtils } from "../prefetcher/MCAssetPrefetchUtils";
import MCUtils from "../utils/MCUtils";
import { MCMediaExporter } from "./MCMediaExporter";

export class FILEAssetExporter implements IMCAssetExporter<FILEAsset> {
  async export(asset: FILEAsset, proxyPath: string, targetDir: string, options?: MCAssetExportOptions): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    const media = await asset.getMediaByProxyPath(proxyPath);
    MCAssetPrefetchUtils.checkAbortSignal(signal);
    //
    // const exportInfo: FILEAssetExportInfo = {
    //
    // }

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
    return mediaExporter.export();
  }
}

interface FILEAssetExportInfo {
  readonly version: string;
  readonly id: string; // 仅记录一个id即可, 单文件模式下 assetId 与 mediaId 一致;
  readonly checksum: string;
}
