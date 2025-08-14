import { MCAssetPrefetchOptions } from "../defines/MCAssetPrefetchOptions";
import { MCAbortSignal } from "../utils/MCAbortController";

export namespace MCAssetPrefetchUtils {
  let mPrefetchId = -1

  export function generatePrefetchId(): number {
    return --mPrefetchId;
  }

  export function getConcurrentPrefetchCount(options?: MCAssetPrefetchOptions): number {
    return options?.concurrentPrefetchCount && options.concurrentPrefetchCount > 0
      ? options.concurrentPrefetchCount : 3; // default: 3;
  }

  export function getChunkSize(options?: MCAssetPrefetchOptions): number {
    return options?.chunkSize && options.chunkSize > 0
      ? options.chunkSize : 5 * 1024 * 1024; // default: 5M;
  }

  export function checkAbortSignal(signal?: MCAbortSignal) {
    if ( signal && signal.isAborted ) {
      throw signal.reason!;
    }
  }
}