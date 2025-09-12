import { MCAssetType } from "../defines/MCAssetType";
import MCConsts from "./MCConsts";

export namespace MCProxyBaseUtils {
  /**
   *  生成代理基路径;
   *
   * baseProxyPath format: `/mc_base_proxy/assetType/assetId/encodedBaseUrl`
   * */
  export function generateBaseProxyPath(
    baseUrl: string,
    assetId: string,
    assetType: MCAssetType
  ): string {
    return `${MCConsts.ROUTE_PATH_PROXY_BASE_URL}/${assetType}/${assetId}/${encodeURIComponent(baseUrl)}`;
  }
}