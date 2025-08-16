import { FILEAsset } from "../asset/filebased/FILEAsset";
import { HLSAsset } from "../asset/hls/HLSAsset";
import { MCAssetManager } from "../asset/MCAssetManager";
import MCAssetUtils from "../asset/MCAssetUtils";
import { MCAssetExportOptions } from "../defines/MCAssetExportOptions";
import { MCAssetType } from "../defines/MCAssetType";
import { MCAssetPrefetchUtils } from "../prefetcher/MCAssetPrefetchUtils";
import { FILEAssetExporter } from "./FILEAssetExporter";
import { HLSAssetExporter } from "./HLSAssetExporter";
import { fileIo } from "@kit.CoreFileKit";

export namespace MCAssetExportManager {
  export async function exportToDirectory(resUrl: string, targetDir: string, options?: MCAssetExportOptions | undefined): Promise<void> {
    const signal = options?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 创建目录
    if ( !fileIo.accessSync(targetDir, fileIo.AccessModeType.EXIST) ) {
      await fileIo.mkdir(targetDir, true);
    }

    // 获取资产
    const requestTarget = await MCAssetUtils.generateProxyPath(resUrl);
    const asset = await MCAssetManager.getInstance().getAssetByRequestTarget(requestTarget);
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 根据资产类型进行导出
    try {
      asset.readwriteRetain();
      switch (asset.type) {
        case MCAssetType.FILE_BASED: {
          const exporter = new FILEAssetExporter();
          return exporter.export(asset as FILEAsset, requestTarget, targetDir, options);
        }
        case MCAssetType.HLS: {
          const exporter = new HLSAssetExporter();
          return exporter.export(asset as HLSAsset, requestTarget, targetDir, options);
        }
        default:
          throw new Error(`Unsupported type: ${asset.type}`);
      }
    }
    finally {
      asset.readwriteRelease();
    }
  }
}