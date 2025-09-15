import { MCAssetType } from '../defines/MCAssetType';
import MCConsts from './MCConsts';

export namespace MCProxyBaseUtils {
  export interface BasedProxyPathInfo {
    readonly baseUrl: string;
    readonly assetId: string;
    readonly assetType: MCAssetType;
    /** 从 basedProxyPath 中 baseUrl 之后的部分 */
    readonly targetPath: string;
  }

  /**
   *  生成代理基路径;
   *
   * baseProxyPath format:
   *   /mc_based_proxy/assetType/assetId/encodedBaseUrl/parentPlaceholderPath/
   */
  export function generateBaseProxyPath(
    baseUrl: string,
    assetId: string,
    assetType: MCAssetType
  ): string {
    return `${MCConsts.ROUTE_PATH_PROXY_BASED}/${assetType}/${assetId}/${encodeURIComponent(baseUrl)}/${generateDashParentPlaceholderPath()}`;
  }

  // basedProxyPath format: `/mc_based_proxy/assetType/assetId/encodedBaseUrl/parentPlaceholderPath/targetPath`
  export function parse(basedProxyPath: string): BasedProxyPathInfo {
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

    const targetPath = resolveDashTargetPath(parts);
    return {
      baseUrl: baseUrl,
      assetId: assetId,
      assetType: assetType,
      targetPath: targetPath,
    };
  }

  /**
   * 生成包含占位符的父路径，用于代替 "../"
   *
   * @returns 形如 "MC_DASH_BPP/MC_DASH_BPP/MC_DASH_BPP/..." 的占位路径
   */
  function generateDashParentPlaceholderPath(): string {
    return `${MCConsts.DASH_PARENT_PATH_PLACEHOLDER}/`.repeat(MCConsts.DASH_PARENT_PATH_MAX_DEPTH);
  }

  /**
   * 将带有占位符的 DASH 路径片段数组解析为最终路径
   *
   * @param parts 路径片段数组，前 5 个是固定信息，从第 6 个开始可能包含占位符
   * @returns 最终拼接的相对路径，例如 "../../video/init.mp4"
   */
  function resolveDashTargetPath(parts: string[]): string {
    // 找到第一个非占位符的位置（从第6个元素开始）
    const relativeParts = parts.slice(5);
    const firstValidIndex = relativeParts.findIndex(it => it !== MCConsts.DASH_PARENT_PATH_PLACEHOLDER);

    if ( firstValidIndex === -1 ) {
      throw new Error(`Invalid baseUrl: unable to locate start index for target path.`);
    }

    // 计算 ../ 的层数：= 最大深度 - 已经消耗的占位符个数
    const depth = MCConsts.DASH_PARENT_PATH_MAX_DEPTH - firstValidIndex;

    // 拼接 ../
    const parentPath = depth > 0 ? "../".repeat(depth) : "";

    // 拼接剩余路径
    return parentPath + relativeParts.slice(firstValidIndex).join("/");
  }
}