import MCAssetCacheManager from "./asset/cachemgr/MCAssetCacheManager";
import MCAssetUtils from "./asset/MCAssetUtils";
import { MCAssetCacheConfig } from "./defines/MCAssetCacheConfig";
import { MCAssetPrefetchOptions } from "./defines/MCAssetPrefetchOptions";
import { MCAssetType } from "./defines/MCAssetType";
import MCAssetPrefetcher from "./prefetcher/MCAssetPrefetcher";
import { MCHttpConnectionHandler } from "./server/MCHttpConnectionHandler";
import { MCTcpSocketServer } from "./server/MCTcpSocketServer";
import MCConfigs from "./utils/MCConfigs";
import MCURL from "./utils/MCURL";

namespace MCMediaCache {
  const mTcpServer = new MCTcpSocketServer();
  const mConnectionHandler = new MCHttpConnectionHandler();
  let mPrepared = false;

  /** 缓存管理配置; 缓存管理器会根据这个配置定期检测并删除一些缓存; */
  export const cacheConfig: MCAssetCacheConfig = MCAssetCacheManager.config;

  /** 启动代理服务器; */
  export async function prepare(): Promise<void> {
    if ( !mPrepared ) {
      // 初始化缓存管理器
      await MCAssetCacheManager.prepare();
      // 启动代理服务器
      mTcpServer.on('connect', (connection) => mConnectionHandler.handleConnection(connection));
      await mTcpServer.start();
      mPrepared = true;
    }
  }

  /** 生成代理播放地址, 播放器可以使用该地址播放; */
  export async function proxy(resUrl: string): Promise<string> {
    return MCAssetUtils.generateProxyUrl(resUrl, await mTcpServer.start());
  }

  /** 预加载; 预先缓存一部分数据到本地; */
  export function prefetch(resUrl: string, options?: MCAssetPrefetchOptions): Promise<void> {
    return MCAssetPrefetcher.prefetch(resUrl, options);
  }

  /** 标记是否"固定"; 缓存管理器会定期删除一些缓存, 如果你想要保留某些视频防止被删除可以提前将其设置为"固定"; */
  export function setPinned(resUrl: string, isPinned: boolean): Promise<void> {
    return MCAssetCacheManager.setPinned(resUrl, isPinned);
  }

  export function isPinned(resUrl: string): Promise<boolean> {
    return MCAssetCacheManager.isPinned(resUrl);
  }

  /** 根据播放地址删除对应的缓存; */
  export function removeCacheBy(resUrl: string): Promise<void> {
    return MCAssetCacheManager.removeCacheBy(resUrl);
  }

  /** 删除本地缓存;
   *
   * 通过`setPinned`被设置为"Pinned"的缓存不会被删除, 如需删除请通过`removeCacheBy`指定 url 来删除;
   *
   * 可删除的缓存大小 = countOfBytesAllCaches() - countOfBytesPinnedCaches();
   *
   * */
  export function removeCaches(): Promise<void> {
    return MCAssetCacheManager.removeCaches();
  }

  /** 缓存大小; */
  export function countOfBytesAllCaches(): Promise<number> {
    return MCAssetCacheManager.countOfBytesAllCaches();
  }

  /** 被固定的缓存大小; */
  export function countOfBytesPinnedCaches(): Promise<number> {
    return MCAssetCacheManager.countOfBytesPinnedCaches();
  }

  /** 对缓存数据加密; 将缓存数据加密保存到本地; */
  export function setDataEncryptHandler(block: (resUrl: string, offset: number, data: ArrayBuffer) => Promise<void>) {
    MCConfigs.dataEncryptHandler = (request, offset, data) => {
      return block(request.url, offset, data);
    }
  }

  /** 对缓存数据解密; */
  export function setDataDecryptHandler(block: (resUrl: string, offset: number, data: ArrayBuffer) => Promise<void>) {
    MCConfigs.dataDecryptHandler = (request, offset, data) => {
      return block(MCURL.parseUrl(request.requestTarget), offset, data);
    };
  }

  /** 返回视频唯一标识; 相同的标识引用同一个缓存;
   *
   * 当出现多个地址指向同一个视频, 例如 url 可能带有鉴权之类的参数, 这部分很容易发生变化, 但这些地址都指向同一个视频, 为了确保只缓存一份视频, 你可以在这里将这些会变化的参数移除;
   *
   * */
  export function setAssetIdentifierGenerator(block: (resUrl: string) => string | Promise<string>) {
    MCConfigs.assetIdentifierGenerator = block;
  }

  /** 资产类型解析;
   *
   * 目前支持两种类型的资产, 你可以返回以下类型:
   *
   * - MCAssetType.FILE_BASED: 基于文件的媒体;
   * - MCAssetType.HLS: 流媒体(m3u8);
   *
   * */
  export function setAssetTypeResolver(block: (resUrl: string) => MCAssetType | Promise<MCAssetType>) {
    MCConfigs.assetTypeResolver = block;
  }
}

export default MCMediaCache;