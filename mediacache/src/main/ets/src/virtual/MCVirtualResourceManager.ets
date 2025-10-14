import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCVirtualResourceType } from "../defines/IMCVirtualResource";
import { MCProxyVirtualResourceUtils } from "../utils/MCProxyVirtualResourceUtils";
import { MCVirtualResourceDataFetcher } from "./MCVirtualResourceDataFetcher";

export interface IMCVirtualResourceManager {
  fetch(clientId: number, request: IMCDataRequest): IMCDataFetcher;
  setResource(key: string, resource: IMCVirtualResourceType | undefined): void;
}

export class MCVirtualResourceManager implements IMCVirtualResourceManager {
  private static shared: IMCVirtualResourceManager;

  private mMap: Map<string, IMCVirtualResourceType> = new Map();

  static getInstance(): IMCVirtualResourceManager {
    if ( !MCVirtualResourceManager.shared ) {
      MCVirtualResourceManager.shared = new MCVirtualResourceManager();
    }
    return MCVirtualResourceManager.shared;
  }

  fetch(clientId: number, request: IMCDataRequest): IMCDataFetcher {
    const proxyPath = request.requestTarget;
    const resourceKey = MCProxyVirtualResourceUtils.parseKey(proxyPath);
    const resource = this.mMap.get(resourceKey);
    if ( !resource ) {
      throw new Error(`Virtual resource not found for key: ${resourceKey}`);
    }

    return new MCVirtualResourceDataFetcher(
      clientId,
      resource,
      request
    );
  }

  setResource(key: string, resource: IMCVirtualResourceType | undefined): void {
    if ( resource ) {
      this.mMap.set(key, resource);
    }
    else {
      this.mMap.delete(key);
    }
  }
}