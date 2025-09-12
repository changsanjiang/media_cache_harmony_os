import { MCAssetType } from "../../defines/MCAssetType";
import { MCProxyBaseUtils } from "../../utils/MCProxyBaseUtils";

export namespace DashProxyUtils {
  export function generateBaseProxyPath(
    baseUrl: string,
    assetId: string,
  ): string {
    return MCProxyBaseUtils.generateBaseProxyPath(baseUrl, assetId, MCAssetType.DASH);
  }
}