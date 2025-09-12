import { url } from '@kit.ArkTS';
import { MCAssetType } from '../defines/MCAssetType';
import { MCMediaKind } from '../defines/MCMediaKind';
import MCConfigs from '../utils/MCConfigs';
import { MCProxyURLUtils } from '../utils/MCProxyURLUtils';
import MCUtils from '../utils/MCUtils';

export namespace MCAssetProxyUtils {
  /**
   * 生成代理地址; 该方法会识别 url 指向的资源是基于文件的媒体还是一个 HLS 资源 或 DASH 资源;
   *
   * 返回资产的代理地址(媒体id和资产id一致), 通过它来访问内部的缓存;
   * */
  export async function generateAssetProxyUrl(resUrl: string, localServerPort: number): Promise<string> {
    const assetType = await determineAssetType(resUrl);
    const assetId = await generateAssetId(resUrl);
    let mediaKind: MCMediaKind;
    switch (assetType) {
      case MCAssetType.FILE_BASED:
        mediaKind = MCMediaKind.FILE;
        break;
      case MCAssetType.HLS:
      case MCAssetType.DASH:
        mediaKind = MCMediaKind.PLAYLIST;
        break;
    }
    const mediaId = assetId; // 根文件的媒体id和资产id一致;
    return MCProxyURLUtils.generateProxyUrl(resUrl, assetId, assetType, mediaId, mediaKind, localServerPort);
  }

  /**
   * 生成代理路径; 该方法会识别 url 指向的资源是基于文件的媒体还是一个 HLS 资源 或 DASH 资源;
   *
   * 返回资产的代理路径(媒体id和资产id一致), 通过它来访问内部的缓存;
   * */
  export async function generateAssetProxyPath(resUrl: string): Promise<string> {
    const assetType = await determineAssetType(resUrl);
    const assetId = await generateAssetId(resUrl);
    let mediaKind: MCMediaKind;
    switch (assetType) {
      case MCAssetType.FILE_BASED:
        mediaKind = MCMediaKind.FILE;
        break;
      case MCAssetType.HLS:
      case MCAssetType.DASH:
        mediaKind = MCMediaKind.PLAYLIST;
        break;
    }
    const mediaId = assetId; // 根文件的媒体id和资产id一致;
    return MCProxyURLUtils.generateProxyPath(resUrl, assetId, assetType, mediaId, mediaKind);
  }

  /**
   * 为每个资产生成一个唯一标识符;
   * */
  export async function generateAssetId(resUrl: string): Promise<string> {
    const target = MCConfigs.assetIdentifierPreprocessor ? (await MCConfigs.assetIdentifierPreprocessor(resUrl)) : resUrl;
    return MCUtils.hash(target);
  }

  /**
   * 确定资产类型; 判断 url 指向是基于文件的媒体还是一个 HLS 资源 或 DASH 资源;
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

    if ( pathname.endsWith(".mpd" ) ) {
      return MCAssetType.DASH;
    }
    return MCAssetType.FILE_BASED;
  }
}