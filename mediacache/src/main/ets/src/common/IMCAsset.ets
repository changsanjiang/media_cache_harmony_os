import { IMCReadwriteReference } from "./IMCReadwriteReference";
import { MCAssetType } from "./MCAssetType";
// import { MCDataType } from "./MCDataType";

// @end
export interface IMCAsset extends IMCReadwriteReference<IMCAsset> {
  readonly type: MCAssetType;
  readonly isStored: Promise<boolean>;
  readonly completeness: Promise<number>; // 完成度; [0, 1];

  prepare(): Promise<void>;
  //createContent(dataType: MCDataType, response: xxx): Promise<xxx>;

}