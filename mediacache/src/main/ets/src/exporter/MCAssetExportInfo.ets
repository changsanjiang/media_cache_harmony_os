import { MCAssetType } from '../defines/MCAssetType';
import { MCMediaKind } from '../defines/MCMediaKind';

export interface MCAssetExportInfo {
  readonly assetId: string;
  readonly assetType: MCAssetType;
  readonly medias: MCMediaExportInfo[];
}

export interface MCMediaExportInfo {
  readonly mediaId: string;
  readonly mediaKind: MCMediaKind;
  // readonly mediaPath: string; // 相对路径
  // readonly metadataPath: string; // 相对路径
}