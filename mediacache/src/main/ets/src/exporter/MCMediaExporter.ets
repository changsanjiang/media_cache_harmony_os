import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCHttpOkResponseHeaders, IMCHttpPartialContentResponseHeaders } from '../defines/IMCHttpResponseHeaders';
import { IMCMedia } from '../defines/IMCMedia';
import { MCMediaDataFetcher } from '../media/MCMediaDataFetcher';
import { MCMediaDataPrefetcher } from '../prefetcher/MCMediaDataPrefetcher';
import { MCAbortSignal } from '../utils/MCAbortController';

export interface IMCMediaExporter {
  export(): Promise<void>;
}

export class MCMediaExporter implements IMCMediaExporter {
  private mClientId: number;
  private mMedia: IMCMedia;
  private mRequest: IMCDataRequest;
  private mTargetDir: string;
  private mOnProgress?: (receivedLength: number, expectedLength: number) => void;
  private mSignal?: MCAbortSignal;

  private mDataFetcher?: IMCDataFetcher;
  private mSerialPromise = Promise.resolve();

  private mCompleted = false;
  private mOnComplete?: (error: Error | undefined) => void = undefined;

  private mReceivedLength: number = 0;
  private mExpectedLength: number = 0;

  constructor(
    clientId: number,
    media: IMCMedia,
    request: IMCDataRequest,
    targetDir: string,
    onProgress?: (receivedLength: number, expectedLength: number) => void,
    signal?: MCAbortSignal
  ) {
    this.mClientId = clientId;
    this.mMedia = media;
    this.mRequest = request;
    this.mTargetDir = targetDir;
    this.mOnProgress = onProgress;
    this.mSignal = signal;
  }

  async export(): Promise<void> {

  }

  private async _export(): Promise<void> {
    // 预加载数据
    const prefecher = new MCMediaDataPrefetcher(
      this.mClientId,
      this.mMedia,
      this.mRequest,
      this.mOnProgress,
      this.mSignal,
    );

    await prefecher.prefetch();

    // copy到目标目录

  }

  private onComplete(error?: Error): void {

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
}