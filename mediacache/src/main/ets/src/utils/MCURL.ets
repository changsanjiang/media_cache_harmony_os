import { MCAssetType } from '../defines/MCAssetType';
import MCConsts from './MCConsts';

namespace MCURL {
  /** proxyUrl format: `http://localhost:port/PROXY_URL/assetType/assetId/encodedURI`;  */
  export function generateProxyUrl(url: string, assetType: MCAssetType, assetId: string, localServerPort: number): string {
    return `http://${MCConsts.LOCALHOST}:${localServerPort}${generateProxyPath(url, assetType, assetId)}`
  }

  /** proxyPath format: `/PROXY_URL/assetType/assetId/encodedURI`; */
  export function generateProxyPath(url: string, assetType: MCAssetType, assetId: string): string {
    return `${MCConsts.PROXY_URL}/${assetType}/${assetId}/${encodeURIComponent(url)}`;
  }

  export interface ProxyTargetInfo {
    readonly url: string;
    readonly assetType: MCAssetType;
    readonly assetId: string;
  }

  export function parse(requestTarget: string): ProxyTargetInfo {
    if ( !requestTarget.startsWith(MCConsts.PROXY_URL) ) {
      throw new Error(`xxx`);
    }

    const parts = requestTarget.split(`/`);
    const assetType: MCAssetType = parseInt(parts[2], 10);
    const assetId = parts[3];
    const url = decodeURIComponent(parts[4]);

    const targetInfo: ProxyTargetInfo = {
      url: url,
      assetType: assetType,
      assetId: assetId
    };
    return targetInfo;
  }

  export function parseUrl(requestTarget: string): string {
    return parse(requestTarget).url;
  }

  export function parseAssetType(requestTarget: string): MCAssetType {
    return parse(requestTarget).assetType;
  }

  export function parseAssetId(requestTarget: string): string {
    return parse(requestTarget).assetId;
  }
}

export default MCURL;