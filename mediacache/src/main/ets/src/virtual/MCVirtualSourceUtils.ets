import { MCProxyVirtualSourceUtils } from "../utils/MCProxyVirtualSourceUtils";

export namespace MCVirtualSourceUtils {
  export async function generateSourceProxyUrl(sourceKey: string, localServerPort: number): Promise<string> {
    return MCProxyVirtualSourceUtils.generateProxyUrl(sourceKey, localServerPort);
  }
}