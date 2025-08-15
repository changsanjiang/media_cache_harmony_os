import { HLSAsset } from "../asset/hls/HLSAsset";
import { IMCAssetExporter } from "../defines/IMCAssetExporter";
import { MCAssetExportOptions } from "../defines/MCAssetExportOptions";

export class HLSAssetExporter implements IMCAssetExporter<HLSAsset> {
  export(asset: HLSAsset, requestTarget: string, targetDir: string, options?: MCAssetExportOptions): Promise<void> {
    throw new Error("Method not implemented.");
  }
}