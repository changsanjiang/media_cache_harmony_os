import MCConsts from "./MCConsts";

/** proxy exported local dir; */
export namespace MCProxyDirUtils {
  export function generateProxyUrl(
    targetDir: string,
    localServerPort: number,
  ): string {
    return `http://${MCConsts.LOCALHOST}:${localServerPort}${generateProxyPath(targetDir)}`;
  }

  /** 生成代理路径;
   *
   * proxyPath format: `/mc_proxy_dir/encodedTargetDirPath`;
   * */
  export function generateProxyPath(
    targetDir: string
  ): string {
    return `${MCConsts.ROUTE_PATH_PROXY_DIR}/${encodeURIComponent(targetDir)}`;
  }
}