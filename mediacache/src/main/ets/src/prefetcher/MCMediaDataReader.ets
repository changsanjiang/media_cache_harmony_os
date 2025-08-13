import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCMedia } from '../defines/IMCMedia';
import { MCMediaDataFetcher } from '../media/MCMediaDataFetcher';
import { MCAbortSignal } from '../utils/MCAbortController';
import MCUtils from '../utils/MCUtils';

/** 注意数据读取量不能过大, 仅适合小文件; */
export interface IMCMediaDataReader {
  read(): Promise<ArrayBuffer | undefined>;
}

export class MCMediaDataReader implements IMCMediaDataReader {
  private mClientId: number;
  private mMedia: IMCMedia;
  private mRequest: IMCDataRequest;
  private mSignal?: MCAbortSignal;

  private mDataFetcher?: IMCDataFetcher = undefined;
  private mData?: ArrayBuffer = undefined;
  private mSerialPromise = Promise.resolve();

  private mCompleted = false;
  private mOnComplete?: (data: ArrayBuffer | undefined, error: Error | undefined) => void = undefined;

  constructor(clientId: number, media: IMCMedia, request: IMCDataRequest, signal?: MCAbortSignal) {
    this.mClientId = clientId;
    this.mMedia = media;
    this.mRequest = request;
    this.mSignal = signal;
  }

  read(): Promise<ArrayBuffer | undefined> {
    return new Promise((resolve, reject) => {
      this._read((data, error) => {
        !error ? resolve(data!) : reject(error);
      });
    });
  }

  private async _read(complete: (data: ArrayBuffer | undefined, error: Error | undefined) => void): Promise<void> {
    this.mOnComplete = complete;

    try {
      this.checkSignal();

      const fetcher: IMCDataFetcher = new MCMediaDataFetcher(this.mClientId, this.mMedia, this.mRequest);
      this.mDataFetcher = fetcher;

      fetcher.on("newDataReadable", (fetcher) => this.readData(fetcher));
      fetcher.on("aborted", (_, e) => this.onFetcherAborted(e));

      this.mSignal?.addEventListener("aborted", (e) => fetcher.abort(e));

      const responseHeaders = await fetcher.prepare();
      switch (responseHeaders.statusCode) {
        case 200: break;
        case 206: break;
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
    this.enqueueTask(async () => {
      if ( this.mCompleted ) {
        return;
      }

      if ( fetcher.isDataEnd ) {
        this.onComplete();
        return
      }

      const readableLength = fetcher.readableLength;
      if ( readableLength == 0 ) {
        return;
      }

      const data = await fetcher.read(readableLength);
      if ( data ) {
        this.mData = this.mData ? MCUtils.mergeArrayBuffers(this.mData, data) : data;

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
    if ( error ) {
      this.mOnComplete?.(undefined, error);
    }
    else {
      this.mOnComplete?.(this.mData, undefined);
    }
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