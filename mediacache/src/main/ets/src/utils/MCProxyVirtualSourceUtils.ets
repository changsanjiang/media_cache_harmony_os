import MCConsts from "./MCConsts";

export namespace MCProxyVirtualSourceUtils {
  export interface VirtualSourcePathInfo {
    readonly sourceKey: string;
  }

  /** 生成代理地址;
   *
   * proxyUrl format: `http://localhost:port/mc_virtual_proxy/encodedSourceKey`;
   * */
  export function generateProxyUrl(
    sourceKey: string,
    localServerPort: number
  ): string {
    return `http://${MCConsts.LOCALHOST}:${localServerPort}${generateProxyPath(sourceKey)}`;
  }

  /** 生成代理路径;
   *
   * proxyPath format: `/mc_virtual_proxy/encodedSourceKey`;
   * */
  export function generateProxyPath(
    sourceKey: string,
  ): string {
    return `${MCConsts.ROUTE_PATH_PROXY_VIRTUAL}/${encodeURIComponent(sourceKey)}`;
  }

  // proxyPath format: `/mc_virtual_proxy/encodedSourceKey`
  export function parse(proxyPath: string): VirtualSourcePathInfo {
    if ( !proxyPath.startsWith(MCConsts.ROUTE_PATH_PROXY_VIRTUAL) ) {
      throw new Error(`Invalid proxy path: expected to start with "${MCConsts.ROUTE_PATH_PROXY_VIRTUAL}", got "${proxyPath}".`);
    }

    const parts = proxyPath.split(`/`);
    // parts 示例: ["", "mc_virtual_proxy", "encodedSourceKey"]
    if ( parts.length < 3 ) {
      throw new Error(
        `Malformed proxy path: expected at least 3 parts, got ${parts.length}. Target: "${proxyPath}".`
      );
    }

    const sourceKey = decodeURIComponent(parts[2]);
    if ( !sourceKey ) {
      throw new Error(`Invalid sourceKey: expected non-empty string at position 2, got "${parts[2]}". Target: "${proxyPath}".`);
    }

    return {
      sourceKey: sourceKey
    }
  }

  export function parseSourceKey(proxyPath: string): string {
    return parse(proxyPath).sourceKey;
  }
}