import { MCAssetType } from "../defines/MCAssetType";
import { MCMediaKind } from "../defines/MCMediaKind";
import MCConsts from "./MCConsts";

/** proxy exported local dir; */
export namespace MCProxyDirUtils {
  /** 生成代理地址;
   *
   * proxyUrl format: `http://localhost:port/mc_proxy/assetType/assetId/mediaKind/mediaId/encodedTargetDir/media.ext`;
   * */
  export function generateProxyUrl(
    targetDir: string,
    assetId: string,
    assetType: MCAssetType,
    mediaId: string,
    mediaKind: MCMediaKind,
    ext: string,
    localServerPort: number,
  ): string {
    return `http://${MCConsts.LOCALHOST}:${localServerPort}${generateProxyPath(targetDir, assetId, assetType, mediaId, mediaKind, ext)}`;
  }

  /** 生成代理路径;
   *
   * proxyPath format: `/mc_proxy/assetType/assetId/mediaKind/mediaId/encodedTargetDir/media.ext`;
   * */
  export function generateProxyPath(
    targetDir: string,
    assetId: string,
    assetType: MCAssetType,
    mediaId: string,
    mediaKind: MCMediaKind,
    ext: string,
  ): string {
    const filename = ext ? `media.${ext}` : `media`;
    return `${MCConsts.ROUTE_PATH_PROXY_DIR}/${assetType}/${assetId}/${mediaKind}/${mediaId}/${encodeURIComponent(targetDir)}/${filename}`;
  }

  export interface ProxyTargetInfo {
    readonly targetDir: string;
    readonly assetType: MCAssetType;
    readonly assetId: string;
    readonly mediaKind: MCMediaKind;
    readonly mediaId: string;
  }

  export function parseTarget(proxyPath: string): ProxyTargetInfo {
    if ( !proxyPath.startsWith(`${MCConsts.ROUTE_PATH_PROXY_DIR}`) ) {
      throw new Error(`Invalid proxy path: expected proxyPath to start with "${MCConsts.ROUTE_PATH_PROXY_DIR}", but got "${proxyPath}".`);
    }

    const parts = proxyPath.split(`/`);
    if (parts.length < 8) {
      throw new Error(`Malformed proxy target: expected at least 7 parts in the proxyPath, but got ${parts.length}. Target: "${proxyPath}".`);
    }

    const assetType: MCAssetType = parseInt(parts[2]);
    const assetId = parts[3];
    const mediaKind = parseInt(parts[4]);
    const mediaId = parts[5];
    const targetDir = decodeURIComponent(parts[6]);

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
    if (!targetDir) {
      throw new Error(`Invalid targetDir: expected a non-empty string at position 6 after decoding, but got "${parts[6]}". Target: "${proxyPath}".`);
    }

    const targetInfo: ProxyTargetInfo = {
      targetDir: targetDir,
      assetType: assetType,
      assetId: assetId,
      mediaKind: mediaKind,
      mediaId: mediaId,
    };
    return targetInfo;
  }

  export function parseTargetDir(proxyPath: string): string {
    return parseTarget(proxyPath).targetDir;
  }
}