import { MCAssetCacheManager } from "./asset/cachemgr/MCAssetCacheManager";
import MCAssetUtils from "./asset/MCAssetUtils";
import { MCAssetCacheConfig } from "./defines/MCAssetCacheConfig";
import { MCAssetPrefetchOptions } from "./defines/MCAssetPrefetchOptions";
import { MCAssetType } from "./defines/MCAssetType";
import MCAssetPrefetcher from "./prefetcher/MCAssetPrefetcher";
import { MCHttpConnectionHandler } from "./server/MCHttpConnectionHandler";
import { IMCTcpSocketServer, MCTcpSocketServer } from "./server/MCTcpSocketServer";
import MCConfigs from "./utils/MCConfigs";
import MCURL from "./utils/MCURL";

namespace MCMediaCache {
  /** 缓存管理配置; 缓存管理器会根据这个配置定期检测并删除一些缓存; */
  export const cacheConfig: MCAssetCacheConfig = new MCAssetCacheConfig();

  /** 生成代理播放地址, 播放器可以使用该地址播放; */
  export async function proxy(resUrl: string): Promise<string> {
    const server = await getLocalServer();
    const port = await server.start();
    return MCAssetUtils.generateProxyUrl(resUrl, port);
  }

  /** 预加载; 预先缓存一部分数据到本地; */
  export function prefetch(resUrl: string, options?: MCAssetPrefetchOptions): Promise<void> {
    return MCAssetPrefetcher.prefetch(resUrl, options);
  }

  /** 标记是否"固定"; 缓存管理器会定期删除一些缓存, 如果你想要保留某些视频防止被删除可以提前将其设置为"固定"; */
  export async function setPinned(resUrl: string, isPinned: boolean): Promise<void> {
    const mgr = await getCacheManager();
    return mgr.setPinned(resUrl, isPinned);
  }

  export async function isPinned(resUrl: string): Promise<boolean> {
    const mgr = await getCacheManager();
    return mgr.isPinned(resUrl);
  }

  /** 根据播放地址删除对应的缓存; */
  export async function removeCacheBy(resUrl: string): Promise<void> {
    const mgr = await getCacheManager();
    return mgr.removeCacheBy(resUrl);
  }

  /** 删除本地缓存;
   *
   * 通过`setPinned`被设置为"Pinned"的缓存不会被删除, 如需删除请通过`removeCacheBy`指定 url 来删除;
   *
   * 可删除的缓存大小 = countOfBytesAllCaches() - countOfBytesPinnedCaches();
   *
   * */
  export async function removeCaches(): Promise<void> {
    const mgr = await getCacheManager();
    return mgr.removeCaches();
  }

  /** 缓存大小; */
  export async function countOfBytesAllCaches(): Promise<number> {
    const mgr = await getCacheManager();
    return mgr.countOfBytesAllCaches();
  }

  /** 被固定的缓存大小; */
  export async function countOfBytesPinnedCaches(): Promise<number> {
    const mgr = await getCacheManager();
    return mgr.countOfBytesPinnedCaches();
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

  /** 资产类型解析; 根据 url 解析相应的资产类型;
   *
   * 目前支持两种类型的资产, 你可以返回以下类型:
   *
   * - MCAssetType.FILE_BASED: 基于文件的媒体;
   * - MCAssetType.HLS: 流媒体(m3u8);
   *
   * 返回 undefined 将采用默认处理;
   * */
  export function setAssetTypeResolver(block: (resUrl: string) => Promise<MCAssetType | undefined>) {
    MCConfigs.assetTypeResolver = block;
  }

  /** 生成资产标识时的预处理器; 当出现多个地址指向同一个视频, 例如 url 可能带有鉴权之类的参数, 这部分很容易发生变化, 但这些地址都指向同一个视频, 为了确保只缓存一份视频, 你可以在这里将这些会变化的参数移除;
   *
   * 相同的标识将引用同一份缓存;
   *
   * 返回 undefined 将采用默认处理;
   * */
  export function setAssetIdentifierPreprocessor(block: (resUrl: string) => Promise<string | undefined>) {
    MCConfigs.assetIdentifierPreprocessor = block;
  }

  let mLocalServerPromise: Promise<IMCTcpSocketServer> | undefined = undefined;
  function getLocalServer(): Promise<IMCTcpSocketServer> {
    if ( mLocalServerPromise === undefined ) {
      mLocalServerPromise = new Promise<IMCTcpSocketServer>((resolve) => {
        const tcpServer = new MCTcpSocketServer();
        const connectionHandler = new MCHttpConnectionHandler();
        tcpServer.on('connect', (connection) => connectionHandler.handleConnection(connection));
        resolve(tcpServer);
      });
    }
    return mLocalServerPromise;
  }

  let mCacheManagerPromise: Promise<MCAssetCacheManager> | undefined = undefined;
  function getCacheManager(): Promise<MCAssetCacheManager> {
    if ( mCacheManagerPromise === undefined ) {
      mCacheManagerPromise = new Promise<MCAssetCacheManager>((resolve) => {
        const cacheManager = new MCAssetCacheManager(cacheConfig);
        resolve(cacheManager.prepare().then(() => cacheManager));
      });
    }
    return mCacheManagerPromise;
  }
}

export default MCMediaCache;