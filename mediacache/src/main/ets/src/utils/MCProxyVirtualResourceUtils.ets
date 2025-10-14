import MCConsts from "./MCConsts";

export namespace MCProxyVirtualResourceUtils {
  export interface VirtualResourcePathInfo {
    readonly resourceKey: string;
  }

  /** 生成代理地址;
   *
   * proxyUrl format: `http://localhost:port/mc_virtual_proxy/encodedResourceKey`;
   * */
  export function generateProxyUrl(
    resourceKey: string,
    localServerPort: number
  ): string {
    return `http://${MCConsts.LOCALHOST}:${localServerPort}${generateProxyPath(resourceKey)}`;
  }

  /** 生成代理路径;
   *
   * proxyPath format: `/mc_virtual_proxy/encodedResourceKey`;
   * */
  export function generateProxyPath(
    resourceKey: string,
  ): string {
    return `${MCConsts.ROUTE_PATH_PROXY_VIRTUAL}/${encodeURIComponent(resourceKey)}`;
  }

  // proxyPath format: `/mc_virtual_proxy/encodedResourceKey`
  export function parse(proxyPath: string): VirtualResourcePathInfo {
    if ( !proxyPath.startsWith(MCConsts.ROUTE_PATH_PROXY_VIRTUAL) ) {
      throw new Error(`Invalid proxy path: expected to start with "${MCConsts.ROUTE_PATH_PROXY_VIRTUAL}", got "${proxyPath}".`);
    }

    const parts = proxyPath.split(`/`);
    // parts 示例: ["", "mc_virtual_proxy", "encodedResourceKey"]
    if ( parts.length < 3 ) {
      throw new Error(
        `Malformed proxy path: expected at least 3 parts, got ${parts.length}. Target: "${proxyPath}".`
      );
    }

    const resourceKey = decodeURIComponent(parts[2]);
    if ( !resourceKey ) {
      throw new Error(`Invalid resourceKey: expected non-empty string at position 2, got "${parts[2]}". Target: "${proxyPath}".`);
    }

    return {
      resourceKey: resourceKey
    }
  }

  export function parseKey(proxyPath: string): string {
    return parse(proxyPath).resourceKey;
  }
}