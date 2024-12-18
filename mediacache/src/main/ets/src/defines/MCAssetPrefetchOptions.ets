import { MCAbortSignal } from "../utils/MCAbortController";

export interface MCAssetPrefetchOptions {

  // 如果 prefetchSize 和 prefetchFileCount 都未设置, 将会预缓存资产中的所有媒体;

  /**
   * 预缓存指定大小(bytes)的的数据;
   *
   * 对于普通媒体文件的预缓存, 除非文件本身小于设置的预取大小, 否则按设置的字节数预取;
   * 对于流媒体(HLS)的预缓存, 会尝试预缓存多个段(ts)文件, 直到下载的数据总大小大于等于设置的预取大小;
   * */
  prefetchSize?: number;

  /**
   * 预缓存指定数量的媒体文件; 这个参数主要用于流媒体(HLS), 因为它的播放列表(playlist)中通常包含多个段(ts)文件, 通过设置这个参数用来指定预缓存的文件数;
   *
   * 指定预缓存的文件数必须大于0.
   *
   * 对于普通媒体文件的预缓存, 因为只包含一个文件, 所以整个媒体文件将被缓存;
   * 对于流媒体(HLS)的预缓存, 会尝试预缓存的指定数量的段(ts)文件;
   * */
  prefetchFileCount?: number;

  /**
   * 指定分块大小; 预加载时可能会尝试分块请求媒体数据;
   *
   * 例如有 50M 的数据, 在预加载时会尝试将这些数据按指定的 chunkSize 分成多个块进行预加载, 可以通过 concurrentPrefetchCount 设置预加载的并发数;
   *
   * 默认值是 5M;
   * */
  chunkSize?: number;

  /**
   * 设置分块预加载时的并发数;
   *
   * 默认值是 3;
   * */
  concurrentPrefetchCount?: number;

  /**
   * 预加载的进度回调;
   * */
  onProgress?: (progress: number) => void;

  additionalHeaders?: Record<string, string>;

  signal?: MCAbortSignal;
}