import { IMCMedia } from "./IMCMedia";
import { IMCReadwriteReference } from "./IMCReadwriteReference";
import { MCAssetType } from "./MCAssetType";

/**
 一个资产中包含单个或多个媒体, 每个媒体对应一个 http 地址;

 这些媒体可能是:
  - File-based medias: mp3, mp4, wav ...
  - HLS medias: playlist(Media1), ts(Media2), key(Media3), variant stream(Media4),  rendition(Media6) ...
 */
export interface IMCAsset extends IMCReadwriteReference<IMCAsset> {
  readonly id: string;
  readonly type: MCAssetType;

  readonly completeness: Promise<number>; // 完成度; [0, 1];

  readonly cacheSize: number; // 返回当前缓存的数据大小;

  prepare(): Promise<void>;
  getMediaBy(requestTarget: string): Promise<IMCMedia>;
}