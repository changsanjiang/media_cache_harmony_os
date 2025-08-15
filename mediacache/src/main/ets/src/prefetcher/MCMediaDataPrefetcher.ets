import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCHttpOkResponseHeaders, IMCHttpPartialContentResponseHeaders } from '../defines/IMCHttpResponseHeaders';
import { IMCMedia } from '../defines/IMCMedia';
import { MCMediaDataFetcher } from '../media/MCMediaDataFetcher';
import { MCAbortSignal } from '../utils/MCAbortController';
import { MCAssetPrefetchUtils } from './MCAssetPrefetchUtils';

export interface IMCMediaDataPrefetcher {
  prefetch(): Promise<void>;
}

export class MCMediaDataPrefetcher implements IMCMediaDataPrefetcher {
  private mClientId: number;
  private mMedia: IMCMedia;
  private mRequest: IMCDataRequest;
  private mOnProgress?: (receivedLength: number, expectedLength: number) => void;
  private mSignal?: MCAbortSignal;

  private mDataFetcher?: IMCDataFetcher;
  private mSerialPromise = Promise.resolve();

  private mCompleted = false;
  private mOnComplete?: (error: Error | undefined) => void = undefined;

  private mReceivedLength: number = 0;
  private mExpectedLength: number = 0;

  constructor(
    media: IMCMedia,
    request: IMCDataRequest,
    onProgress?: (receivedLength: number, expectedLength: number) => void,
    signal?: MCAbortSignal
  ) {
    this.mClientId = MCAssetPrefetchUtils.generatePrefetchId();
    this.mMedia = media;
    this.mRequest = request;
    this.mOnProgress = onProgress;
    this.mSignal = signal;
  }

  prefetch(): Promise<void> {
    return new Promise((resolve, reject) => {
      this._prefetch((error) => {
        !error ? resolve() : reject(error);
      });
    });
  }

  private async _prefetch(complete: (error: Error | undefined) => void): Promise<void> {
    this.mOnComplete = complete;

    try {
      this.checkSignal();

      const fetcher = new MCMediaDataFetcher(this.mClientId, this.mMedia, this.mRequest);
      this.mDataFetcher = fetcher;

      fetcher.on("newDataReadable", (fetcher) => this.readData(fetcher));
      fetcher.on("aborted", (_, e) => this.onFetcherAborted(e));

      this.mSignal?.addEventListener("aborted", (e) => fetcher.abort(e));

      const responseHeaders = await fetcher.prepare();
      switch (responseHeaders.statusCode) {
        case 200:
          // mExpectedLength 不一定有值, 当数据以 chunked 形式响应时, 无法获取所请求的数据长度;
          this.mExpectedLength = (responseHeaders as IMCHttpOkResponseHeaders).contentLength ?? 0;
          break;
        case 206:
          this.mExpectedLength = (responseHeaders as IMCHttpPartialContentResponseHeaders).contentRange.length;
          break;
        default:
          throw new Error(`Invalid response with code: ${responseHeaders.statusCode}}`);
      }

      this.readData(fetcher);
    }
    catch (e) {
      this.onComplete(e);
    }
  }

  private readData(fetcher: IMCDataFetcher): void {
    this.enqueueTask(() => {
      if ( this.mCompleted ) {
        return;
      }

      // 数据读取完毕
      if ( fetcher.isDataEnd ) {
        this.onComplete();
        return;
      }

      const readableLength = fetcher.readableLength;
      if ( readableLength == 0 ) {
        return;
      }

      if ( fetcher.seek(fetcher.offset + readableLength) ) {
        this.mReceivedLength += readableLength;

        // mExpectedLength 不一定有值, 当数据以 chunked 形式响应时, 无法获取所请求的数据长度;
        if ( this.mExpectedLength > 0 ) {
          this.mOnProgress?.(this.mReceivedLength, this.mExpectedLength);
        }

        // 再次检测数据是否已读取完毕
        if ( fetcher.isDataEnd ) {
          this.onComplete();
        }
      }
    });
  }

  private onFetcherAborted(e: Error): void {
    this.onComplete(e);
  }

  private onComplete(error?: Error): void {
    if ( this.mCompleted ) {
      return;
    }

    const fetcher = this.mDataFetcher;
    if ( fetcher ) {
      this.mDataFetcher = undefined;

      fetcher.off('newDataReadable');
      fetcher.off('aborted');

      if ( !fetcher.isCompleted ) {
        fetcher.abort(error);
      }
    }

    this.mCompleted = true;
    this.mOnComplete?.(error);
  }

  // 确保操作按顺序串行执行
  private enqueueTask(task: () => void | Promise<void>): void {
    this.mSerialPromise = this.mSerialPromise
      .then(async () => {
        if ( this.mCompleted ) {
          return;
        }
        return task(); // 执行新任务
      })
      .catch((e: Error) => this.onComplete(e)) // 捕获异常
  }

  private checkSignal(): void {
    if ( this.mSignal && this.mSignal.isAborted ) {
      throw this.mSignal.reason!;
    }
  }
}