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
    const proxyPath = await MCAssetUtils.generateAssetProxyPath(resUrl);
    const asset = await MCAssetManager.getInstance().getAssetByProxyPath(proxyPath);
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 根据资产类型进行导出
    try {
      asset.readwriteRetain();
      switch (asset.type) {
        case MCAssetType.FILE_BASED: {
          const exporter = new FILEAssetExporter();
          await exporter.export(asset as FILEAsset, proxyPath, targetDir, options);
          break;
        }
        case MCAssetType.HLS: {
          const exporter = new HLSAssetExporter();
          await exporter.export(asset as HLSAsset, proxyPath, targetDir, options);
          break;
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