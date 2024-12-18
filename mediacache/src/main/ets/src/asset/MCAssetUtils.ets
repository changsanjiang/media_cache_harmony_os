import { url } from '@kit.ArkTS';
import { MCURL, MCUtils } from '../../../../../Index';
import { MCAssetType } from '../defines/MCAssetType';
import MCConfigs from '../utils/MCConfigs';

namespace MCAssetUtils {
  /**
   * 生成代理地址; 该方法会识别 url 指向的资源是基于文件的媒体还是一个 HLS 资源;
   *
   * 通过这个方法生成的代理地址都是根地址;
   * */
  export async function generateProxyUrl(resUrl: string, localServerPort: number): Promise<string> {
    const assetType = await resolveAssetType(resUrl);
    const assetId = await generateAssetId(resUrl);
    const mediaId = assetId; // 根文件的媒体id和资产id一致;
    return MCURL.generateProxyUrl(resUrl, localServerPort, assetType, assetId, mediaId);
  }

  export async function generateProxyPath(resUrl: string): Promise<string> {
    const assetType = await resolveAssetType(resUrl);
    const assetId = await generateAssetId(resUrl);
    const mediaId = assetId; // 根文件的媒体id和资产id一致;
    return MCURL.generateProxyPath(resUrl, assetType, assetId, true, mediaId);
  }

  /**
   * 为 hls 的媒体生成代理路径;
   *
   * isRoot: 当 absoluteUrl 指向一个新的 playlist(variant stream or rendition) 时传 true;
   * */
  export async function generateHLSProxyPath(resUrl: string, isRoot: boolean, masterAssetId: string): Promise<string> {
    const assetType = MCAssetType.HLS;
    const assetId = isRoot ? (await generateAssetId(resUrl)) : masterAssetId;
    const mediaId = isRoot ? assetId : (await generateMediaId(resUrl)); // 根文件的媒体id和资产id一致;
    return MCURL.generateProxyPath(resUrl, assetType, assetId, isRoot, mediaId);
  }

  /**
   * 为资产生成一个唯一标识符;
   * */
  export async function generateAssetId(resUrl: string): Promise<string> {
    const target = MCConfigs.assetIdentifierGenerator ? (await MCConfigs.assetIdentifierGenerator(resUrl)) : resUrl;
    return MCUtils.hash(target);
  }

  /**
   * 为媒体生成一个唯一标识符;
   * */
  export async function generateMediaId(resUrl: string): Promise<string> {
    return MCUtils.hash(resUrl);
  }

  /**
   * 识别一个 url 指向的资源是基于文件的媒体还是一个 HLS 资源;
   * */
  async function resolveAssetType(resUrl: string): Promise<MCAssetType> {
    if ( MCConfigs.assetTypeResolver ) {
      return MCConfigs.assetTypeResolver(resUrl);
    }

    const pathname = url.URL.parseURL(resUrl).pathname;
    if ( pathname.endsWith('.m3u8') || pathname.endsWith('.m3u') ) {
      return MCAssetType.HLS;
    }
    return MCAssetType.FILE_BASED;
  }
}

export default MCAssetUtils;