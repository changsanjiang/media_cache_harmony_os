import { IMCAsset } from './IMCAsset';
import { MCAssetExportOptions } from './MCAssetExportOptions';

/** 用于导出资产所有媒体数据; */
export interface IMCAssetExporter<T extends IMCAsset> {
  /**
   * 导出资产媒体数据到指定目录;
   *
   * 导出过程中如果媒体数据仅存在部分缓存, 则会发起网络请求获取剩余数据, 如果缓存都已存在, 则不会请求网络;
   *
   * @param targetDir 目标目录绝对路径;
   * @param options 导出选项(是否覆盖目录文件等选项);
   * @returns Promise<void>;
   */
  export(asset: T, proxyPath: string, targetDir: string, options?: MCAssetExportOptions): Promise<void>;
}