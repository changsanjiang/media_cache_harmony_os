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
import { IMCVirtualSource, IMCVirtualSourceType } from './defines/IMCVirtualSource';
import { MCVirtualSourceManager } from './virtual/MCVirtualSourceManager';
import { MCVirtualSourceUtils } from './virtual/MCVirtualSourceUtils';
import { MCProxyVirtualSourceUtils } from './utils/MCProxyVirtualSourceUtils';

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
   * 代理指定的数据源;
   *
   * 可将任意数据源 (本地文件、内存数据、动态生成流等) 映射为可通过 URL 访问的媒体资源;
   *
   * #### 工作原理:
   * - 通过 `MCMediaCache.proxyVirtualSource` 获取数据源代理 URL;
   * - 当外部组件 (例如播放器) 请求该 URL 时, 实际不会发起真实网络请求,
   * - 请求将被路由到内部虚拟代理服务, 数据由`setVirtualSource()` 配置的 `virtualSource` 提供;
   *
   * #### 使用示例:
   * - 将代理 URL 设置给播放器;
   * - 播放器获取播放数据时, 对播放器来说, 它只是请求了一个 URL, 与真实 URL 无异;
   * - 数据将从 virtualSource 获取, 可以是本地文件、内存数据、加密数据、生成的数据流、甚至经过转换的媒体内容;
   * ```ts
   * const key = 'key-local-audio'; // key 必须唯一, 通过 setVirtualSource 配置数据源, 全局配置一次即可
   * MCMediaCache.setVirtualSource(key, { filePath: '/path/to/audio.mp3' });
   *
   * // 在需要播放时获取数据源代理 URL
   * const proxyUrl = await MCMediaCache.proxyVirtual(key);
   *
   * // 播放器无感知这是虚拟数据源
   * player.url = proxyUrl;
   * ```
   *
   * #### 使用场景
   * 可用于:
   * - 将加密或私有存储的本地文件伪装为网络资源;
   * - 将实时生成的数据 (如音频流、转码数据) 暴露为标准 URL;
   * - 统一播放器输入接口, 无需关心真实数据来源;
   *
   * @note
   * 请通过 `setVirtualSource` 设置数据源, `sourceKey` 将作为数据源标识;
   *
   * @note
   * 解密数据仍然通过`setDataDecryptionHandler`进行配置, 在解密回调中 `resUrl` 将变为 `sourceKey`;
   */
  export async function proxyVirtualSource(sourceKey: string): Promise<string> {
    return MCVirtualSourceUtils.generateSourceProxyUrl(sourceKey, await mTcpServer.start());
  }

  /**
   * 设置数据源;
   *
   * 此方法用于为 `proxyVirtualSource()` 生成的虚拟 URL 提供实际数据来源;
   *
   * #### 说明:
   * - 当虚拟 URL 被访问时，系统将根据 `sourceKey` 找到对应的数据源;
   * - 数据源可为本地文件、内存缓冲、或其他实现了 `IMCVirtualDataSource` 的对象;
   * - 设置为 `undefined` 时表示移除绑定;
   *
   * @param sourceKey 数据源标识符, 要确保全局唯一性;
   * @param source 虚拟数据源对象或 `undefined`;
   *
   * @note
   * 当数据源不再使用时, 可传入 `undefined` 移除绑定;
   *
   * @note
   * 该数据源不参与缓存管理;
   * */
  export function setVirtualSource(sourceKey: string, source: IMCVirtualSourceType | undefined): void {
    MCVirtualSourceManager.getInstance().setSource(sourceKey, source);
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
   * 请求前回调处理器;
   *
   * 在向远程服务器发起请求前调用, 可在此对请求对象进行修改,
   * 例如添加自定义请求头、cookie等;
   *
   * @example
   * MCMediaCache.setRequestHandler((request) => {
   *  request.setHeader('key', 'value');
   * });
   */
  export function setRequestHandler(block: (request: MCDownloadRequest) => void): void {
    MCConfigs.requestHandler = block;
  }

  /** 对缓存数据加密;
   *
   * - 可直接修改 data, 也可以返回一个新的 ArrayBuffer(新 buffer 的数据长度不可改变, byteLength 必须与 data.byteLength 一致);
   * - 加密后的数据会被存储到本地;
   * */
  export function setDataEncryptionHandler(block: (resUrl: string, offset: number, data: ArrayBuffer) => Promise<void | ArrayBuffer>): void {
    MCConfigs.dataEncryptionHandler = (request, offset, data) => {
      return block(request.url, offset, data);
    }
  }

  /** 对缓存数据解密;
   *
   * - 可直接修改 data, 也可以返回一个新的 ArrayBuffer(新 buffer 的数据长度不可改变, byteLength 必须与 data.byteLength 一致);
   * - 解密后的数据会被传递给播放器;
   * */
  export function setDataDecryptionHandler(block: (resUrl: string, offset: number, data: ArrayBuffer) => Promise<void | ArrayBuffer>): void {
    MCConfigs.dataDecryptionHandler = (request, offset, data) => {
      const proxyPath = request.requestTarget;
      if ( proxyPath.startsWith(MCConsts.ROUTE_PATH_PROXY_URL) ) {
        return block(MCProxyURLUtils.parseTargetUrl(request.requestTarget), offset, data);
      }
      else if ( proxyPath.startsWith(MCConsts.ROUTE_PATH_PROXY_DIR) ) {
        return block(MCProxyDirUtils.parseTargetDir(request.requestTarget), offset, data);
      }
      else if ( proxyPath.startsWith(MCConsts.ROUTE_PATH_PROXY_VIRTUAL) ) {
        return block(MCProxyVirtualSourceUtils.parseSourceKey(request.requestTarget), offset, data);
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

  /**
   * 变体流(多码率)手动选择器;
   *
   * 当 Master Playlist 包含多个 `#EXT-X-STREAM-INF` 条目时, 可通过该回调手动选择一个需要保留的变体流, 其他变体流将从 Master Playlist 中移除,
   * 返回 `undefined` 时将保留所有变体流;
   *
   * 例如以下变体流二选一:
   *
   * ```m3u8
   * #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="audio-group"
   * https://example.com/low/index.m3u8
   *
   * #EXT-X-STREAM-INF:BANDWIDTH=3000000,AVERAGE-BANDWIDTH=2500000,RESOLUTION=1280x720,FRAME-RATE=60,
   * CODECS="avc1.4d4028,mp4a.40.2",AUDIO="audio-group",SUBTITLES="subs-group"
   * https://example.com/high/index.m3u8
   * ```
   *
   * @note
   * - 返回 `undefined` 时将保留所有变体流;
   * - `playlistOriginalUrl` 表示最初请求的 Master Playlist 地址；
   *   `playlistCurrentUrl` 表示经过可能的 HTTP 重定向后的实际地址;
   */
  export function setVariantStreamSelectionHandler(block: HLSVariantStreamSelectionHandler | undefined): void {
    MCConfigs.variantStreamSelectionHandler = block;
  }

  /**
   * 衍生流(Rendition)手动选择器;
   *
   * 当通过 `HLSVariantStreamSelectionHandler` 选择的变体流包含关联的衍生流 (例如 AUDIO 或 SUBTITLES) 时,
   * 将触发该回调, 以便在每个衍生流组中手动选择一个需要保留的衍生流;
   * 未被选中的衍生流将从 Master Playlist 中移除,
   * 返回 `undefined` 时将保留该组中的所有衍生流;
   *
   * 例如以下变体流包含 AUDIO 和 SUBTITLES 关联:
   *
   * ```m3u8
   * #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="audio",SUBTITLES="subs"
   * https://example.com/low/index.m3u8
   *
   * # AUDIO renditions（二选一）
   * #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",LANGUAGE="en",URI="audio_eng.m3u8"
   * #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Spanish",LANGUAGE="es",URI="audio_spa.m3u8"
   *
   * # SUBTITLES renditions（二选一）
   * #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",LANGUAGE="en",URI="subs_eng.m3u8"
   * #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="Spanish",LANGUAGE="es",URI="subs_spa.m3u8"
   * ```
   *
   * @note
   * - 返回 `undefined` 时将保留该组中的所有衍生流;
   * - `playlistOriginalUrl` 表示最初请求的 Master Playlist 地址;
   *   `playlistCurrentUrl` 表示经过可能的 HTTP 重定向后的实际地址;
   */
  export function setRenditionSelectionHandler(block: HLSRenditionSelectionHandler | undefined): void {
    MCConfigs.renditionSelectionHandler = block;
  }

  export function setDashAdaptationSetSelectionHandler(block: DashAdaptationSetSelectionHandler | undefined): void {
    MCConfigs.dashAdaptationSetSelectionHandler = block;
  }

  export function setDashRepresentationSelectionHandler(block: DashRepresentationSelectionHandler | undefined): void {
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