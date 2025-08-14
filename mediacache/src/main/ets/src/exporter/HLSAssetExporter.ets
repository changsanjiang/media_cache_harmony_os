import { IMCAssetExporter } from "../defines/IMCAssetExporter";
import { MCAssetExportOptions } from "../defines/MCAssetExportOptions";

export class HLSAssetExporter implements IMCAssetExporter {
  exportToDirectory(targetDir: string, options?: MCAssetExportOptions | undefined): Promise<void> {
    throw new Error("Method not implemented.");
  }
}