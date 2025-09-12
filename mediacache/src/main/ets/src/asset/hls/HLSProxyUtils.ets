import { MCAssetType } from "../../defines/MCAssetType";
import { MCMediaKind } from "../../defines/MCMediaKind";
import { MCMediaIdGenerator } from "../../utils/MCMediaIdGenerator";
import { MCProxyURLUtils } from "../../utils/MCProxyURLUtils";

export namespace HLSProxyUtils {
  /**
   * 为 hls 的媒体生成代理路径;
   *
   * 代理 hls 中的各个媒体片段;
   * */
  export async function generateProxyPathForHLSMedia(assetId: string, mediaKind: MCMediaKind, mediaUrl: string): Promise<string> {
    const mediaId = await MCMediaIdGenerator.generate(mediaUrl);
    return MCProxyURLUtils.generateProxyPath(mediaUrl, assetId, MCAssetType.HLS, mediaId, mediaKind);
  }
}