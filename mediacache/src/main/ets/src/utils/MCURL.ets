import { MCAssetType } from '../defines/MCAssetType';
import { MCMediaKind } from '../defines/MCMediaKind';
import MCConsts from './MCConsts';

export namespace MCURL {
  /** 生成代理地址;
   *
   * proxyUrl format: `http://localhost:port/mc_proxy/assetType/assetId/mediaKind/mediaId/encodedURI`;
   * */
  export function generateProxyUrl(resUrl: string, localServerPort: number, assetType: MCAssetType, assetId: string, mediaKind: MCMediaKind, mediaId: string): string {
    return `http://${MCConsts.LOCALHOST}:${localServerPort}${generateProxyPath(resUrl, assetType, assetId, mediaKind, mediaId)}`
  }

  /** 生成代理路径;
   *
   * proxyPath format: `/mc_proxy/assetType/assetId/mediaKind/mediaId/encodedURI`;
   * */
  export function generateProxyPath(resUrl: string, assetType: MCAssetType, assetId: string, mediaKind: MCMediaKind, mediaId: string): string {
    return `${MCConsts.PATH_PROXY_URL}/${assetType}/${assetId}/${mediaKind}/${mediaId}/${encodeURIComponent(resUrl)}`;
  }
 
  export interface ProxyTargetInfo {
    readonly url: string;
    readonly assetType: MCAssetType;
    readonly assetId: string;
    readonly mediaKind: MCMediaKind;
    readonly mediaId: string;
  }

  export function parseTarget(proxyPath: string): ProxyTargetInfo {
    if (!proxyPath.startsWith(MCConsts.PATH_PROXY_URL)) {
      throw new Error(`Invalid proxy target: expected proxyPath to start with "${MCConsts.PATH_PROXY_URL}", but got "${proxyPath}".`);
    }

    const parts = proxyPath.split(`/`);
    if (parts.length < 7) {
      throw new Error(`Malformed proxy target: expected at least 7 parts in the proxyPath, but got ${parts.length}. Target: "${proxyPath}".`);
    }

    const assetType: MCAssetType = parseInt(parts[2]);
    const assetId = parts[3];
    const mediaKind = parseInt(parts[4]);
    const mediaId = parts[5];
    const url = decodeURIComponent(parts[6]);

    if (isNaN(assetType)) {
      throw new Error(`Invalid assetType: expected a number at position 2, but got "${parts[2]}". Target: "${proxyPath}".`);
    }
    if (!assetId) {
      throw new Error(`Invalid assetId: expected a non-empty string at position 3, but got "${parts[3]}". Target: "${proxyPath}".`);
    }
    if (isNaN(mediaKind)) {
      throw new Error(`Invalid mediaKind: expected a number at position 4, but got "${parts[4]}". Target: "${proxyPath}".`);
    }
    if (!mediaId) {
      throw new Error(`Invalid mediaId: expected a non-empty string at position 5, but got "${parts[5]}". Target: "${proxyPath}".`);
    }
    if (!url) {
      throw new Error(`Invalid URL: expected a non-empty string at position 6 after decoding, but got "${parts[6]}". Target: "${proxyPath}".`);
    }

    const targetInfo: ProxyTargetInfo = {
      url: url,
      assetType: assetType,
      assetId: assetId,
      mediaKind: mediaKind,
      mediaId: mediaId,
    };
    return targetInfo;
  }

  export function parseTargetUrl(proxyPath: string): string {
    return parseTarget(proxyPath).url;
  }
}