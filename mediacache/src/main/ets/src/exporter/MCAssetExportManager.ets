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
import { IMCAsset } from "../defines/IMCAsset";
import { MCProxyDirUtils } from "../utils/MCProxyDirUtils";
import { MCLocalFILEAsset } from "./MCLocalFILEAsset";
import { MCLocalHLSAsset } from "./MCLocalHLSAsset";

export interface IMCAssetExportManager {
  getAssetByProxyPath(proxyPath: string): Promise<IMCAsset>;
  exportToDirectory(resUrl: string, targetDir: string, options?: MCAssetExportOptions | undefined): Promise<void>;
}

export class MCAssetExportManager implements IMCAssetExportManager {
  private static shared: IMCAssetExportManager;

  static getInstance(): IMCAssetExportManager {
    if ( !MCAssetExportManager.shared ) {
      MCAssetExportManager.shared = new MCAssetExportManager();
    }
    return MCAssetExportManager.shared;
  }


  private mAssets: Map<string, IMCAsset> = new Map();
  private mSerialPromise: Promise<void> = Promise.resolve();

  /**
   * 根据代理路径获取对应资产对象.
   */
  getAssetByProxyPath(proxyPath: string): Promise<IMCAsset> {
    return this.enqueueTask(async () => {
      const targetInfo = MCProxyDirUtils.parseTarget(proxyPath);
      const assetId = targetInfo.assetId;
      const assetType = targetInfo.assetType;
      const assetDir = targetInfo.targetDir;

      const key = `${assetId}_${assetDir}`;
      const asset = this.mAssets.get(key) ?? await this.initAsset(key, assetId, assetType, assetDir);
      return asset;
    });
  }

  async exportToDirectory(resUrl: string, targetDir: string, options?: MCAssetExportOptions | undefined): Promise<void> {
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

  private enqueueTask<T>(task: () => Promise<T>): Promise<T> {
    const run = this.mSerialPromise
      .catch((err: Error) => {  // swallow previous errors
        console.error('Previous task failed:', err);
      })
      .then(() => task());

    // Maintain the chain
    this.mSerialPromise = run.then(() => {}, (err: Error) => {
      console.error('Previous task failed:', err);
    });
    return run;
  }

  private async initAsset(key: string, assetId: string, assetType: MCAssetType, assetDir: string): Promise<IMCAsset> {
    let asset: IMCAsset;
    switch (assetType) {
      case MCAssetType.FILE_BASED:
        asset = new MCLocalFILEAsset(assetId, assetDir);
        break;
      case MCAssetType.HLS:
        asset = new MCLocalHLSAsset(assetId, assetDir);
        break;
      case MCAssetType.DASH:
        throw new Error(`TODO(DASH)`);
    }
    await asset.prepare();

    this.mAssets.set(key, asset);
    return asset;
  }
}