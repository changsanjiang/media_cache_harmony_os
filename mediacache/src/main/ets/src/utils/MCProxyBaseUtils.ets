import { MCAssetType } from "../defines/MCAssetType";
import { MCMediaKind } from "../defines/MCMediaKind";
import MCConsts from "./MCConsts";
import { MCMediaIdGenerator } from "./MCMediaIdGenerator";
import { MCProxyURLUtils } from "./MCProxyURLUtils";

export namespace MCProxyBaseUtils {
  /**
   *  生成代理基路径;
   *
   * baseProxyPath format:
   *   /mc_based_proxy/assetType/assetId/encodedBaseUrl/targetPath
   */
  export function generateBaseProxyPath(
    baseUrl: string,
    assetId: string,
    assetType: MCAssetType
  ): string {
    return `${MCConsts.ROUTE_PATH_PROXY_BASED}/${assetType}/${assetId}/${encodeURIComponent(baseUrl)}`;
  }

  /**
   * 将通过基请求的路径转为代理路径(proxy path);
   *
   * 例如:
   * basedProxyPath: `/mc_based_proxy/assetType/assetId/encodedBaseUrl/chunk-stream0-00001.m4s`
   * convert to proxyPath: `/mc_proxy/assetType/assetId/mediaKind/mediaId/encodedURI`;
   * */
  export async function convertToProxyPath(
    basedProxyPath: string,
    mediaKind: MCMediaKind = MCMediaKind.FILE,
  ): Promise<string> {
    const info = parse(basedProxyPath);
    const mediaUrl = info.baseUrl + info.targetPath;
    const mediaId = await MCMediaIdGenerator.generate(mediaUrl);
    return MCProxyURLUtils.generateProxyPath(
      mediaUrl,
      info.assetId,
      info.assetType,
      mediaId,
      mediaKind
    );
  }

  interface BasedProxyPathInfo {
    readonly baseUrl: string;
    readonly assetId: string;
    readonly assetType: MCAssetType;
    /** 从 basedProxyPath 中 baseUrl 之后的部分 */
    readonly targetPath: string;
  }

  // basedProxyPath format: `/mc_based_proxy/assetType/assetId/encodedBaseUrl/targetPath`
  function parse(basedProxyPath: string): BasedProxyPathInfo {
    if ( !basedProxyPath.startsWith(MCConsts.ROUTE_PATH_PROXY_BASED) ) {
      throw new Error(`Invalid based proxy path: expected to start with "${MCConsts.ROUTE_PATH_PROXY_BASED}", got "${basedProxyPath}".`);
    }

    const parts = basedProxyPath.split(`/`);
    // parts 示例: ["", "mc_based_proxy", "assetType", "assetId", "encodedBaseUrl", "targetPath"]
    if (parts.length < 6) {
      throw new Error(
        `Malformed based proxy path: expected at least 6 parts, got ${parts.length}. Target: "${basedProxyPath}".`
      );
    }

    const assetType: MCAssetType = parseInt(parts[2]);
    if ( isNaN(assetType) ) {
      throw new Error(`Invalid assetType: expected a number at position 2, got "${parts[2]}". Target: "${basedProxyPath}".`);
    }

    const assetId = parts[3];
    if ( !assetId ) {
      throw new Error(`Invalid assetId: expected non-empty string at position 3, got "${parts[3]}". Target: "${basedProxyPath}".`);
    }

    const baseUrl = decodeURIComponent(parts[4]);
    if ( !baseUrl ) {
      throw new Error(`Invalid baseUrl: expected non-empty string at position 4, got "${parts[4]}". Target: "${basedProxyPath}".`);
    }

    const targetPath = '/' + parts.slice(5).join('/');
    return {
      baseUrl: baseUrl,
      assetId: assetId,
      assetType: assetType,
      targetPath: targetPath,
    };
  }
}