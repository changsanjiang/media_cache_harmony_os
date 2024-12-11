import { MCAbortSignal } from "../utils/MCAbortController";

namespace MCAssetPrefetcher {
  export interface MCAssetPrefetchOptions {
    /**
     * 预缓存指定大小(bytes)的的数据;
     *
     * 对于普通的媒体文件的预缓存, 除非文件本身小于设置的预取大小, 否则按设置的字节数预取;
     * 对于流媒体(HLS)的预缓存, 会尝试预缓存多个段文件(ts文件), 直到下载的数据总大小大于等于设置的预取大小;
     * */
    prefetchSize?: number;

    /**
     * 预缓存指定数量的媒体文件; 这个参数主要用于流媒体(HLS), 因为它的播放列表中通常包含多个段(ts)文件;
     *
     * 指定的预取文件数必须大于0.
     *
     * 对于普通的媒体文件的预缓存, 因为只包含一个文件, 所以整个媒体文件将被缓存;
     * 对于流媒体(HLS)的预缓存, 会尝试预缓存的指定数量的段文件(ts文件);
     * */
    prefetchFileCount?: number;
    onProgress?: (progress: number) => void;
    signal?: MCAbortSignal;
  }

  export async function prefetch(resUrl: string, options?: MCAssetPrefetchOptions): Promise<void> {

  }
}