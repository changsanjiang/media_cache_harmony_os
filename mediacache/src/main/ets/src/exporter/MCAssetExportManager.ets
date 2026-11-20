import { MCAssetCapabilityRegistry } from "../asset/MCAssetCapabilityRegistry";
import { MCAssetManager } from "../asset/MCAssetManager";
import { MCAssetProxyUtils } from "../asset/MCAssetProxyUtils";
import { MCAssetExportOptions } from "../defines/MCAssetExportOptions";
import { MCAssetType } from "../defines/MCAssetType";
import { MCAssetPrefetchUtils } from "../prefetcher/MCAssetPrefetchUtils";
import { MCRequestScope } from "../utils/MCRequestScope";
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
    const proxyPath = await MCAssetProxyUtils.generateAssetProxyPath(resUrl);
    const asset = await MCAssetManager.getInstance().getAssetByProxyPath(proxyPath);
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 不支持导出的类型（如 DASH）在 Registry 内 assert 并抛错
    await MCRequestScope.withAsset(asset, async () => {
      await MCAssetCapabilityRegistry.exportAsset(asset, proxyPath, targetDir, options);
    });
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
      default:
        MCAssetCapabilityRegistry.assertLocalDirPlaySupported(assetType);
        throw new Error(`Unsupported local asset type: ${MCAssetType[assetType]}`);
    }
    await asset.prepare();

    this.mAssets.set(key, asset);
    return asset;
  }
}