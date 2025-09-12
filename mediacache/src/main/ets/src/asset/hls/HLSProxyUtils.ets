import { MCAssetType } from "../../defines/MCAssetType";
import { MCMediaKind } from "../../defines/MCMediaKind";
import { MCProxyURLUtils } from "../../utils/MCProxyURLUtils";
import MCUtils from "../../utils/MCUtils";

export namespace HLSProxyUtils {
  /**
   * 为 hls 的媒体生成代理路径;
   *
   * 代理 hls 中的各个媒体片段;
   * */
  export async function generateProxyPathForHLSMedia(assetId: string, mediaKind: MCMediaKind, mediaUrl: string): Promise<string> {
    const mediaId = await generateMediaId(mediaUrl);
    return MCProxyURLUtils.generateProxyPath(mediaUrl, assetId, MCAssetType.HLS, mediaId, mediaKind);
  }

  /**
   * 为 hls 的每个媒体生成一个唯一标识符;
   * */
  async function generateMediaId(resUrl: string): Promise<string> {
    return MCUtils.hash(resUrl);
  }
}