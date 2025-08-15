import { FILEAsset } from "../asset/filebased/FILEAsset";
import { IMCAssetExporter } from "../defines/IMCAssetExporter";
import { MCAssetExportOptions } from "../defines/MCAssetExportOptions";

export class FILEAssetExporter implements IMCAssetExporter<FILEAsset> {
  export(asset: FILEAsset, requestTarget: string, targetDir: string, options?: MCAssetExportOptions): Promise<void> {

    throw new Error("Method not implemented.");
  }
}