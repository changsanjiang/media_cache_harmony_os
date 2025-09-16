import MCAssetCacheManager from './asset/cachemgr/MCAssetCacheManager';
import { MCAssetProxyUtils } from './asset/MCAssetProxyUtils';
import { HLSRenditionSelectionHandler, HLSVariantStreamSelectionHandler } from './defines/HLSDefines';
import { MCAssetCacheConfig } from './defines/MCAssetCacheConfig';
import { MCAssetPrefetchOptions } from './defines/MCAssetPrefetchOptions';
import { MCAssetType } from './defines/MCAssetType';
import { MCLogLevel } from './defines/MCLogLevel';
import { MCLogModule } from './defines/MCLogModule';
import { MCAssetPrefetchManager } from './prefetcher/MCAssetPrefetchManager';
import { MCHttpConnectionHandler } from './server/MCHttpConnectionHandler';
import { MCTcpSocketServer } from './server/MCTcpSocketServer';
import MCConfigs from './utils/MCConfigs';
import { MCDownloadRequest } from './utils/MCDownloadRequest';
import MCLogger from './utils/MCLogger';
import { MCProxyURLUtils } from './utils/MCProxyURLUtils';
import { rcp } from '@kit.RemoteCommunicationKit';
import { MCAssetExportOptions } from './defines/MCAssetExportOptions';
import { MCAssetExportManager } from './exporter/MCAssetExportManager';
import { MCAssetExportUtils } from './exporter/MCAssetExportUtils';
import MCConsts from './utils/MCConsts';
import { MCProxyDirUtils } from './utils/MCProxyDirUtils';
import { DashAdaptationSetSelectionHandler, DashRepresentationSelectionHandler } from './defines/DashDefines';

export namespace MCMediaCache {
  const mTcpServer = new MCTcpSocketServer();
  const mConnectionHandler = new MCHttpConnectionHandler();

  /** 缓存管理配置; 缓存管理器会根据该配置, 定期检测并自动删除部分缓存文件; */
  export const cacheConfig: MCAssetCacheConfig = MCAssetCacheManager.config;

  let mPrepared = false;
  let mPreparePromise: Promise<void> | undefined = undefined;

  /**
   * 初始化以启动代理、缓存管理器等;
   *
   * @note 请在使用其他接口之前调用;
   * */
  export async function prepare(context: Context): Promise<void> {
    if ( mPrepared ) {
      return;
    }

    if ( mPreparePromise ) {
      return mPreparePromise;
    }

    const promise = _prepare(context);
    mPreparePromise = promise;
    mPreparePromise.then(() => {
      mPrepared = true;
    }).finally(() => {
      mPreparePromise = undefined;
    });
    return promise;
  }

  /**
   * 生成代理播放地址;
   *
   * 播放器使用该地址播放即可实现 边播放边缓存;
   */
  export async function proxy(resUrl: string): Promise<string> {
    return MCAssetProxyUtils.generateAssetProxyUrl(resUrl, await mTcpServer.start());
  }

  /**
   * 预缓存媒体数据;
   *
   * 可在播放前预先缓存一部分数据到本地, 以提升首帧加载速度和播放体验;
   */
  export function prefetch(resUrl: string, options?: MCAssetPrefetchOptions): Promise<void> {
    return MCAssetPrefetchManager.prefetch(resUrl, options);
  }

  /**
   * 导出媒体数据到指定目录(相当于把媒体数据下载到指定的目录);
   *
   * - 如果媒体数据仅有部分缓存，将自动发起网络请求补齐剩余部分;
   * - 如果缓存已完整存在，则不会请求网络;
   *
   * @param targetDir 导出目录的绝对路径;
   * @param options 导出选项(是否覆盖目录文件等选项);
   * @returns Promise<void>;
   *
   * @note
   * - 导出的媒体可通过调用 `proxyDir` 获取代理地址进行播放;
   * - 对于 HLS (m3u8),建议先调用 `prefetch` 将所有片段预缓存, 再调用 `exportToDirectory`，可以提升导出效率;
   */
  export function exportToDirectory(resUrl: string, targetDir: string, options?: MCAssetExportOptions): Promise<void> {
    return MCAssetExportManager.getInstance().exportToDirectory(resUrl, targetDir, options);
  }

  /**
   * 代理指定目录进行播放;
   *
   * 当媒体数据通过 `exportToDirectory` 导出到本地后, 可以调用该接口生成代理地址用于播放;
   *
   * @param targetDir 已导出媒体数据的目录绝对路径;
   * @returns Promise<string> 代理播放地址;
   * */
  export async function proxyDir(targetDir: string): Promise<string> {
    return MCAssetExportUtils.generateAssetProxyUrl(targetDir, await mTcpServer.start());
  }

  /**
   * 设置缓存是否固定(Pinned);
   *
   * 缓存管理器会定期清理部分缓存, 如果需要保留某些资源防止被删除, 可以将其设置为 "固定";
   */
  export function setPinned(resUrl: string, isPinned: boolean): Promise<void> {
    return MCAssetCacheManager.setPinned(resUrl, isPinned);
  }

  /** 判断某个缓存是否已被固定; */
  export function isPinned(resUrl: string): Promise<boolean> {
    return MCAssetCacheManager.isPinned(resUrl);
  }

  /**
   * 删除本地缓存;
   *
   * 可删除缓存大小 = `totalCacheSize()` - `pinnedCacheSize()`;
   *
   * @note
   * - 通过 `setPinned` 设置为固定的缓存不会被删除;
   * - 如需删除固定缓存(Pinned)，请使用 `removeCacheBy` 指定 URL 删除;
   */
  export function removeCaches(): Promise<void> {
    return MCAssetCacheManager.removeCaches();
  }

  /** 删除指定的缓存; */
  export function removeCacheBy(resUrl: string): Promise<void> {
    return MCAssetCacheManager.removeCacheBy(resUrl);
  }

  /** 所有缓存的大小(包含被固定的缓存); */
  export function totalCacheSize(): Promise<number> {
    return MCAssetCacheManager.totalCacheSize();
  }

  /** 获取被固定的缓存大小 */
  export function pinnedCacheSize(): Promise<number> {
    return MCAssetCacheManager.pinnedCacheSize();
  }

  /** 是否开启控制台输出日志; */
  export function setLogEnabled(isEnabled: boolean): void {
    MCLogger.enabled = isEnabled;
  }

  /** 设置日志等级; */
  export function setLogLevel(level: MCLogLevel): void {
    MCLogger.logLevel = level;
  }

  /** 禁止哪些模块的日志; */
  export function setLogBlockModules(modules: MCLogModule[]): void {
    MCLogger.blacklist = modules;
  }

  /** 允许哪些模块的日志; */
  export function setLogWhiteModules(modules: MCLogModule[]): void {
    MCLogger.whitelist = modules;
  }

  /**
   * 请求拦截器;
   *
   * 在向远程服务器发起请求前触发, 可在回调中修改请求(例如添加请求头);
   */
  export function setRequestHandler(block: (request: MCDownloadRequest) => void): void {
    MCConfigs.requestHandler = block;
  }

  /** 对缓存数据加密;
   *
   * - 可直接修改 data, 也可以返回一个新的 ArrayBuffer(新 buffer 的数据长度不可改变, byteLength 必须与 data.byteLength 一致);
   * - 加密后的数据会被存储到本地;
   * */
  export function setDataEncryptHandler(block: (resUrl: string, offset: number, data: ArrayBuffer) => Promise<void | ArrayBuffer>): void {
    MCConfigs.dataEncryptHandler = (request, offset, data) => {
      return block(request.url, offset, data);
    }
  }

  /** 对缓存数据解密;
   *
   * - 可直接修改 data, 也可以返回一个新的 ArrayBuffer(新 buffer 的数据长度不可改变, byteLength 必须与 data.byteLength 一致);
   * - 解密后的数据会被传递给播放器;
   * */
  export function setDataDecryptHandler(block: (resUrl: string, offset: number, data: ArrayBuffer) => Promise<void | ArrayBuffer>): void {
    MCConfigs.dataDecryptHandler = (request, offset, data) => {
      const proxyPath = request.requestTarget;
      if ( proxyPath.startsWith(MCConsts.ROUTE_PATH_PROXY_URL) ) {
        return block(MCProxyURLUtils.parseTargetUrl(request.requestTarget), offset, data);
      }
      else if ( proxyPath.startsWith(MCConsts.ROUTE_PATH_PROXY_DIR) ) {
        return block(MCProxyDirUtils.parseTargetDir(request.requestTarget), offset, data);
      }
      return Promise.resolve();
    };
  }

  /** 资产类型解析; 根据 url 解析相应的资产类型;
   *
   * 你可以返回以下类型:
   *
   * - MCAssetType.FILE_BASED: 基于文件的媒体;
   * - MCAssetType.HLS: 流媒体(m3u8);
   * - MCAssetType.DASH: MPEG-DASH;
   *
   * 返回 undefined 将采用默认处理;
   * */
  export function setAssetTypeResolver(block: (resUrl: string) => Promise<MCAssetType | undefined>): void {
    MCConfigs.assetTypeResolver = block;
  }

  /** 生成资产标识时的预处理器; 当出现多个地址指向同一个视频, 例如 url 可能带有鉴权之类的参数, 这部分很容易发生变化, 但这些地址都指向同一个视频, 为了确保只缓存一份视频, 你可以在这里将这些会变化的参数移除;
   *
   * 相同的标识将引用同一份缓存;
   *
   * 返回 undefined 将采用默认处理;
   * */
  export function setAssetIdentifierPreprocessor(block: (resUrl: string) => Promise<string | undefined>): void {
    MCConfigs.assetIdentifierPreprocessor = block;
  }

  /** hls variant stream 选择器; */
  export function setVariantStreamSelectionHandler(block: HLSVariantStreamSelectionHandler): void {
    MCConfigs.variantStreamSelectionHandler = block;
  }

  /** hls rendition 选择器 */
  export function setRenditionSelectionHandler(block: HLSRenditionSelectionHandler): void {
    MCConfigs.renditionSelectionHandler = block;
  }

  export function setDashAdaptationSetSelectionHandler(block: DashAdaptationSetSelectionHandler): void {
    MCConfigs.dashAdaptationSetSelectionHandler = block;
  }

  export function setDashRepresentationSelectionHandler(block: DashRepresentationSelectionHandler): void {
    MCConfigs.dashRepresentationSelectionHandler = block;
  }

  export function setDownloadSessionConfiguration(configuration: rcp.SessionConfiguration | undefined): void {
    MCConfigs.sessionConfiguration = configuration;
  }

  /** 设置发送给客户端的数据块大小; */
  export function setSocketDataBufferSize(size: number): void {
    MCConfigs.socketDataBufferSize = size;
  }

  async function _prepare(context: Context): Promise<void> {
    mTcpServer.on('connect', (connection) => mConnectionHandler.handleConnection(connection));
    // 初始化缓存管理器
    // 启动代理服务器
    await Promise.all([MCAssetCacheManager.prepare(context), mTcpServer.start()]);
  }
}