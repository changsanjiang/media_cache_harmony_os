import MCAssetCacheManager from "./asset/cachemgr/MCAssetCacheManager";
import MCAssetUtils from "./asset/MCAssetUtils";
import { MCAssetPrefetchOptions } from "./defines/MCAssetPrefetchOptions";
import MCAssetPrefetcher from "./prefetcher/MCAssetPrefetcher";
import { MCHttpConnectionHandler } from "./server/MCHttpConnectionHandler";
import { MCTcpSocketServer } from "./server/MCTcpSocketServer";

namespace MCMediaCache {
  const mTcpServer = new MCTcpSocketServer();
  const mConnectionHandler = new MCHttpConnectionHandler();
  let mPrepared = false;

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

  /** 标记是否"固定"; 缓存管理器会根据配置定期检测并删除一些缓存, 如果你想要保留某些视频防止被删除可以设置为"固定"; */
  export function setPinned(resUrl: string, isPinned: boolean): Promise<void> {
    return MCAssetCacheManager.setPinned(resUrl, isPinned);
  }

  export function isPinned(resUrl: string): Promise<boolean> {
    return MCAssetCacheManager.isPinned(resUrl);
  }
}

export default MCMediaCache;