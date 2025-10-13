import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCVirtualSourceType } from "../defines/IMCVirtualSource";
import { MCProxyVirtualSourceUtils } from "../utils/MCProxyVirtualSourceUtils";
import { MCVirtualSourceDataFetcher } from "./MCVirtualSourceDataFetcher";

export interface IMCVirtualSourceManager {
  fetch(clientId: number, request: IMCDataRequest): IMCDataFetcher;
  setSource(key: string, source: IMCVirtualSourceType | undefined): void;
}

export class MCVirtualSourceManager implements IMCVirtualSourceManager {
  private static shared: IMCVirtualSourceManager;

  private mMap: Map<string, IMCVirtualSourceType> = new Map();

  static getInstance(): IMCVirtualSourceManager {
    if ( !MCVirtualSourceManager.shared ) {
      MCVirtualSourceManager.shared = new MCVirtualSourceManager();
    }
    return MCVirtualSourceManager.shared;
  }

  fetch(clientId: number, request: IMCDataRequest): IMCDataFetcher {
    const proxyPath = request.requestTarget;
    const sourceKey = MCProxyVirtualSourceUtils.parseSourceKey(proxyPath);
    const source = this.mMap.get(sourceKey);
    if ( !source ) {
      throw new Error(`Virtual source not found for key: ${sourceKey}`);
    }

    return new MCVirtualSourceDataFetcher(
      clientId,
      source,
      request
    );
  }

  setSource(key: string, source: IMCVirtualSourceType | undefined): void {
    if ( source ) {
      this.mMap.set(key, source);
    }
    else {
      this.mMap.delete(key);
    }
  }
}