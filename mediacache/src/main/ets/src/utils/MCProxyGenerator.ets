import HLSDefines from '../defines/HLSDefines';
import MCConsts from './MCConsts';

namespace MCProxyGenerator {
  export function generateProxyURLFromURL(url: string, localServerPort: number): string {
    if ( url.includes(MCConsts.PATH_PROXY) ) {
      return url;
    }
    return `http://${MCConsts.LOCALHOST}:${localServerPort}${MCConsts.PATH_PROXY}/${encodeURIComponent(url)}`
  }

  export function restoreURLFromProxyTarget(requestTarget: string): string | undefined {
    if ( requestTarget.startsWith(MCConsts.PATH_PROXY) ) {
      return decodeURIComponent(requestTarget.substring(MCConsts.PATH_PROXY.length + 1));
    }
    return undefined;
  }

  export function generateProxyURIForHLSItem(assetId: string, absoluteUrl: string, itemType: HLSDefines.ItemType): string {
    return `${MCConsts.PATH_HLS_ITEM}/${assetId}/${itemType}/${encodeURIComponent(absoluteUrl)}`;
  }
}

export default MCProxyGenerator;