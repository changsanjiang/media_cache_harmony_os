import { IMCAssetReader } from "./IMCAssetReader";
import { IMCHttpRequest } from "./IMCHttpRequest";
import { IMCReadwriteReference } from "./IMCReadwriteReference";

/**
 一个资产中包含单个或多个媒体, 每个媒体对应一个 http 地址;

 这些媒体可能是:
  - File-based medias: mp3, mp4, wav ...
  - HLS medias: playlist(Media1), ts(Media2), key(Media3), variant stream(Media4),  rendition(Media6) ...
 */
export interface IMCAsset extends IMCReadwriteReference<IMCAsset> {
  readonly id: string;

  readonly isStored: Promise<boolean>;
  readonly completeness: Promise<number>; // 完成度; [0, 1];

  prepare(): Promise<void>;
  createReaderBy(clientId: number, request: IMCHttpRequest, decrypt?: (request: IMCHttpRequest, offset: number, data: ArrayBuffer, len: number) => number | Promise<number>): Promise<IMCAssetReader>;
}