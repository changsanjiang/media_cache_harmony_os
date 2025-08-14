import { IMCAssetExporter } from "../defines/IMCAssetExporter";
import { MCAssetExportOptions } from "../defines/MCAssetExportOptions";

export class FILEAssetExporter implements IMCAssetExporter {
  exportToDirectory(targetDir: string, options?: MCAssetExportOptions): Promise<void> {
    throw new Error("Method not implemented.");
  }
}