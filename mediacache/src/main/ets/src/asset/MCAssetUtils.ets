import { url } from '@kit.ArkTS';
import { MCAssetType } from '../defines/MCAssetType';
import { MCMediaKind } from '../defines/MCMediaKind';
import MCConfigs from '../utils/MCConfigs';
import { MCProxyURLUtils } from '../utils/MCProxyURLUtils';
import MCUtils from '../utils/MCUtils';

namespace MCAssetUtils {
  /**
   * 生成代理地址; 该方法会识别 url 指向的资源是基于文件的媒体还是一个 HLS 资源;
   *
   * 返回资产的代理地址(媒体id和资产id一致), 通过它来访问内部的缓存;
   * */
  export async function generateProxyUrl(resUrl: string, localServerPort: number): Promise<string> {
    const assetType = await determineAssetType(resUrl);
    const assetId = await generateAssetId(resUrl);
    const mediaKind = assetType === MCAssetType.HLS ? MCMediaKind.PLAYLIST : MCMediaKind.FILE;
    const mediaId = assetId; // 根文件的媒体id和资产id一致;
    return MCProxyURLUtils.generateProxyUrl(resUrl, assetType, assetId, mediaKind, mediaId, localServerPort);
  }

  /**
   * 生成代理路径; 该方法会识别 url 指向的资源是基于文件的媒体还是一个 HLS 资源;
   *
   * 返回资产的代理路径(媒体id和资产id一致), 通过它来访问内部的缓存;
   * */
  export async function generateProxyPath(resUrl: string): Promise<string> {
    const assetType = await determineAssetType(resUrl);
    const assetId = await generateAssetId(resUrl);
    const mediaKind = assetType === MCAssetType.HLS ? MCMediaKind.PLAYLIST : MCMediaKind.FILE;
    const mediaId = assetId; // 根文件的媒体id和资产id一致;
    return MCProxyURLUtils.generateProxyPath(resUrl, assetType, assetId, mediaKind, mediaId);
  }

  /**
   * 为 hls 的媒体生成代理路径;
   *
   * 代理 hls 中的各个媒体片段;
   * */
  export async function generateHLSProxyPath(assetId: string, mediaKind: MCMediaKind, mediaUrl: string): Promise<string> {
    const mediaId = await generateMediaId(mediaUrl);
    return MCProxyURLUtils.generateProxyPath(mediaUrl, MCAssetType.HLS, assetId, mediaKind, mediaId);
  }

  /**
   * 资产唯一标识符;
   * */
  export async function generateAssetId(resUrl: string): Promise<string> {
    const target = MCConfigs.assetIdentifierPreprocessor ? (await MCConfigs.assetIdentifierPreprocessor(resUrl)) : resUrl;
    return MCUtils.hash(target);
  }

  /**
   * 确定资产类型; 判断 url 指向是基于文件的媒体还是一个 HLS 资源;
   * */
  async function determineAssetType(resUrl: string): Promise<MCAssetType> {
    if ( MCConfigs.assetTypeResolver ) {
      const assetType = await MCConfigs.assetTypeResolver(resUrl);
      if ( assetType !== undefined ) {
        return assetType;
      }
    }

    const pathname = url.URL.parseURL(resUrl).pathname;
    if ( pathname.endsWith('.m3u8') || pathname.endsWith('.m3u') ) {
      return MCAssetType.HLS;
    }
    return MCAssetType.FILE_BASED;
  }

  /**
   * 为媒体生成一个唯一标识符;
   * */
  async function generateMediaId(resUrl: string): Promise<string> {
    return MCUtils.hash(resUrl);
  }
}

export default MCAssetUtils;