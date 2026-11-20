import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { MCLogModule } from '../defines/MCLogModule';
import { MCAssetManager } from '../asset/MCAssetManager';
import { MCAssetProxyUtils } from '../asset/MCAssetProxyUtils';
import { MCAssetExportManager } from '../exporter/MCAssetExportManager';
import { MCVirtualResourceManager } from '../virtual/MCVirtualResourceManager';
import { MCMediaHttpSession } from '../session/MCMediaHttpSession';
import MCConsts from '../utils/MCConsts';
import MCLogger from '../utils/MCLogger';

/**
 * 代理路径 → {@link IMCDataFetcher}；server 内唯一依赖 Asset/Export/Virtual 的入口。
 */
export class MCHttpProxyRouter {
  static async resolveFetcher(
    clientId: number,
    requestTarget: string,
    dataRequest: IMCDataRequest
  ): Promise<IMCDataFetcher> {
    MCLogger.debug(MCLogModule.MCHttpProxyRouter, () => MCLogger.withClient(clientId, `route ${requestTarget}`));

    if (requestTarget.startsWith(MCConsts.ROUTE_PATH_PROXY_URL)) {
      const asset = await MCAssetManager.getInstance().getAssetByProxyPath(requestTarget);
      return new MCMediaHttpSession(clientId, asset, dataRequest);
    }
    if (requestTarget.startsWith(MCConsts.ROUTE_PATH_PROXY_DIR)) {
      const asset = await MCAssetExportManager.getInstance().getAssetByProxyPath(requestTarget);
      return new MCMediaHttpSession(clientId, asset, dataRequest);
    }
    if (requestTarget.startsWith(MCConsts.ROUTE_PATH_PROXY_VIRTUAL)) {
      return MCVirtualResourceManager.getInstance().fetch(clientId, dataRequest);
    }

    throw new Error(
      `[clientId: ${clientId}] Invalid request target: "${requestTarget}". ` +
        `Expected path to start with "/${MCConsts.ROUTE_PATH_PROXY_URL}", "/${MCConsts.ROUTE_PATH_PROXY_DIR}", or "/${MCConsts.ROUTE_PATH_PROXY_VIRTUAL}".`
    );
  }

  // requestTarget: proxyPath
  // The request target path (e.g., /mc_proxy/xxx、/mc_dir_proxy/xxx、/mc_virtual_proxy/xxx)
  static async normalizeRequestTarget(clientId: number, requestTarget: string): Promise<string> {
    if (requestTarget.startsWith(MCConsts.ROUTE_PATH_PROXY_BASED)) {
      MCLogger.debug(MCLogModule.MCHttpProxyRouter, () => MCLogger.withClient(clientId, `based_proxy convert ${requestTarget}`));
      return await MCAssetProxyUtils.convertToProxyPath(requestTarget);
    }
    return requestTarget;
  }
}