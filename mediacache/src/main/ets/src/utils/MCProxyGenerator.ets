import HLSDefines from '../defines/HLSDefines';
import MCConsts from './MCConsts';

namespace MCProxyGenerator {
  export function generateProxyURLFromURL(url: string, localServerPort: number): string {
    if ( url.includes(MCConsts.PATH_PROXY) ) {
      return url;
    }

    // TODO: 确定是否需要把对应的 mediaId 也加进去？

    return `http://${MCConsts.LOCALHOST}:${localServerPort}${MCConsts.PATH_PROXY}/${encodeURIComponent(url)}`
  }

  export function restoreURLFromProxyTarget(requestTarget: string): string {
    if ( !requestTarget.startsWith(MCConsts.PATH_PROXY) ) {
      // TODO: next
      throw new Error(`xxx`);
    }
    return decodeURIComponent(requestTarget.substring(MCConsts.PATH_PROXY.length + 1));
  }

  export function generateProxyURIForHLSItem(assetId: string, absoluteUrl: string, itemType: HLSDefines.ItemType): string {
    return `${MCConsts.PATH_HLS_ITEM}/${assetId}/${itemType}/${encodeURIComponent(absoluteUrl)}`;
  }

  export function getMediaIdByProxyTarget(requestTarget: string): string {
    return '';
  }
}

export default MCProxyGenerator;