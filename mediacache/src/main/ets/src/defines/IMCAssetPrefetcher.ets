import { IMCAsset } from "./IMCAsset";
import { MCAssetPrefetchOptions } from "./MCAssetPrefetchOptions";

/** 用于预缓存资产媒体数据; */
export interface IMCAssetPrefetcher<T extends IMCAsset> {
  prefetch(asset: T, proxyPath: string, options?: MCAssetPrefetchOptions): Promise<void>;
}