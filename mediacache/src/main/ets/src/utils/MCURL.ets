import { MCAssetType } from '../defines/MCAssetType';
import MCConsts from './MCConsts';

namespace MCURL {
  /** proxyUrl format: `http://localhost:port/PATH_PROXY_URL/assetType/assetId/root/mediaId/encodedURI`;
   *
   * 通过这个方法生成的代理地址都是根地址;
   * */
  export function generateProxyUrl(resUrl: string, localServerPort: number, assetType: MCAssetType, assetId: string, mediaId: string): string {
    return `http://${MCConsts.LOCALHOST}:${localServerPort}${generateProxyPath(resUrl, assetType, assetId, true,
      mediaId)}`
  }

  /**
   * isRoot: 是否是根文件; 基于文件的媒体都是根文件; 如果是 hls, 则 playlist 是根文件, aes key, ts 等都属于 sub 文件;
   *
   * root proxyPath format: `PATH_PROXY_URL/assetType/assetId/root/mediaId/encodedURI`;
   * sub proxyPath format: `PATH_PROXY_URL/assetType/assetId/sub/mediaId/encodedURI`;
   * */
  export function generateProxyPath(resUrl: string, assetType: MCAssetType, assetId: string, isRoot: boolean, mediaId: string): string {
    return `${MCConsts.PATH_PROXY_URL}/${assetType}/${assetId}/${isRoot ? "root" :
      "sub"}/${mediaId}/${encodeURIComponent(resUrl)}`;
  }

  export interface ProxyTargetInfo {
    readonly url: string;
    readonly assetType: MCAssetType;
    readonly assetId: string;
    readonly isRoot: boolean; // 是否是根文件; 根文件的媒体id和资产id一致;
    readonly mediaId: string;
  }

  export function parse(requestTarget: string): ProxyTargetInfo {
    if (!requestTarget.startsWith(MCConsts.PATH_PROXY_URL)) {
      throw new Error(`xxx`);
    }

    const parts = requestTarget.split(`/`);
    const assetType: MCAssetType = parseInt(parts[2], 10);
    const assetId = parts[3];
    const isRoot = parts[4] === `root`;
    const mediaId = parts[5];
    const url = decodeURIComponent(parts[6]);

    const targetInfo: ProxyTargetInfo = {
      url: url,
      assetType: assetType,
      assetId: assetId,
      isRoot: isRoot,
      mediaId: mediaId,
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

  export function parseRoot(requestTarget: string): boolean {
    return parse(requestTarget).isRoot;
  }

  export function parseMediaId(requestTarget: string): string {
    return parse(requestTarget).mediaId;
  }
}

  export default MCURL;