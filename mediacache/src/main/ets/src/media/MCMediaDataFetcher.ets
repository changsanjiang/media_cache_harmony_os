import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCDataOkResponse, IMCDataPartialContentResponse, IMCDataResponse } from '../defines/IMCDataResponse';
import { IMCMediaContentLoader } from '../defines/IMCMediaContentLoader';
import { MCLogModule } from '../defines/MCLogModule';
import { MCAbortController } from '../utils/MCAbortController';
import MCLogger from '../utils/MCLogger';
import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { IMCMedia } from '../defines/IMCMedia';
import {
  IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders
} from '../defines/IMCHttpResponseHeaders';
import { MCMediaContentLoaderState } from '../defines/MCMediaContentLoaderState';

export class MCMediaDataFetcher implements IMCDataFetcher {
  private mMedia: IMCMedia;
  private mClientId: number;
  private mRequest: IMCDataRequest;

  private mDataEnd = false;
  private mAborted = false;

  private mFetchAbortController?: MCAbortController = undefined;
  private mResponse?: IMCDataResponse = undefined;
  private mLoaders?: IMCMediaContentLoader[] = undefined;
  private mCurrentLoader?: IMCMediaContentLoader = undefined;
  private mError?: Error = undefined; // aborted 状态时必定有值;
  private mMediaAbortCallback = (error: Error) => this.abort(error);

  private mOnNewDataReadable?: (fetcher: IMCDataFetcher) => void = undefined;
  private mOnAborted?: (fetcher: IMCDataFetcher, error?: Error | undefined) => void = undefined;
  private mOnDataEnd?: (fetcher: IMCDataFetcher) => void = undefined;

  constructor(clientId: number, media: IMCMedia, request: IMCDataRequest) {
    this.mClientId = clientId;
    this.mMedia = media;
    this.mRequest = request;

    media.readwriteRetain();
  }

  get isReady(): boolean {
    return this.mResponse != undefined;
  }

  get isCompleted(): boolean {
    return this.mDataEnd || this.mAborted;
  }

  get isAborted(): boolean {
    return this.mAborted;
  }

  get isDataEnd(): boolean {
    return this.mDataEnd;
  }

  get offset(): number {
    return this.mCurrentLoader?.offset ?? 0;
  }

  get readableLength(): number {
    return this.mCurrentLoader?.readableLength ?? 0;
  }

  async prepare(): Promise<IMCHttpResponseHeaders> {
    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Starting prepare for request: ${JSON.stringify(this.mRequest)}}`);
    this.mMedia.abortSignal.addEventListener('aborted', this.mMediaAbortCallback);

    if (this.mAborted) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted.`);
      throw this.mError!;
    }

    this.mFetchAbortController = new MCAbortController();

    try {
      const response = await this.mMedia.fetch(this.mRequest, this.mFetchAbortController.signal);
      this.mFetchAbortController = undefined;
      this.onPrepare(response);
      return this.generateResponseHeaders(response);
    }
    catch (error) {
      MCLogger.warn(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Media fetch failed during prepare: ${error?.message}`);
      this.mFetchAbortController = undefined;
      this.onError(error);
      throw this.mError ?? error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    const result = await this.mCurrentLoader?.read(capacity);
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Read ${result?.byteLength ?? 0} bytes from current loader.`);
    return result;
  }

  //  只允许在当前可读范围内 seek;
  seek(offset: number): boolean {
    const currentLoader = this.mCurrentLoader;
    if ( currentLoader && currentLoader.state == MCMediaContentLoaderState.Ready ) {
      const rangeStart = currentLoader.offset;
      const rangeEnd = currentLoader.offset + currentLoader.readableLength;
      if ( offset < rangeStart || offset > rangeEnd ) {
        return false;
      }

      const result = currentLoader.seek(offset);
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Seek to offset ${offset} ${result ? "succeeded" : "failed"}.`);
      return result;
    }
    return false;
  }

  abort(error?: Error | undefined): void {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting fetcher${error ? ` due to error: ${error.message}` : ""}. Stack trace: ${error?.stack || 'none'}}`,);

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as aborted. response: ${this.mResponse}, currentLoader: ${this.mCurrentLoader}, loaders.length: ${this.mLoaders?.length}`);

    this.mAborted = true;
    this.mError = error ?? new Error('Fetcher was aborted');

    // 外部调用 abort 时, 如果此时正在执行 media.fetch 则尝试取消;
    if ( this.mFetchAbortController ) {
      this.mFetchAbortController.abort(this.mError);
      this.mFetchAbortController = undefined;
    }

    this.clear(this.mError);

    this.mMedia.abortSignal.removeEventListener('aborted', this.mMediaAbortCallback);
    this.mMedia.readwriteRelease();

    Promise.resolve().then(() => {
      this.mOnAborted?.(this, this.mError);
    });
  }

  private done(): void {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as done.`);

    this.mDataEnd = true;
    this.mMedia.abortSignal.removeEventListener('aborted', this.mMediaAbortCallback);
    this.mMedia.readwriteRelease();
    // 不需要 clear, loader 都是通过 shift 从 mLoaders 推出的, 此时 mLoaders 为空数组;
    this.mCurrentLoader = undefined;

    Promise.reject().then(() => {
      this.mOnDataEnd?.(this);
    });
  }

  private clear(error?: Error | undefined): void {
    if ( this.mLoaders ) {
      for (let loader of this.mLoaders) {
        loader.off('stateChange');
        loader.off('newDataReadable');

        if ( loader.state != MCMediaContentLoaderState.Ended && loader.state != MCMediaContentLoaderState.Aborted ) {
          loader.abort(error);
        }
      }
      this.mLoaders = undefined;
    }
  }

  on(event: 'newDataReadable', callback: (fetcher: IMCDataFetcher) => void): void;
  on(event: 'aborted', callback: (fetcher: IMCDataFetcher, error?: Error) => void): void;
  on(event: 'dataEnd', callback: (fetcher: IMCDataFetcher) => void): void;
  on(event: string, callback: Object): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = callback as (fetcher: IMCDataFetcher) => void;
        break;
      case 'aborted':
        this.mOnAborted = callback as (fetcher: IMCDataFetcher, error?: Error | undefined) => void;
        break;
      case 'dataEnd':
        this.mOnDataEnd = callback as (fetcher: IMCDataFetcher) => void;;
        break;
    }
  }

  off(event: 'newDataReadable'): void;
  off(event: 'aborted'): void;
  off(event: 'dataEnd'): void;
  off(event: string): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = undefined;
        break;
      case 'aborted':
        this.mOnAborted = undefined;
        break;
      case 'dataEnd':
        this.mOnDataEnd = undefined;
        break;
    }
  }

  private onPrepare(response: IMCDataResponse): void {
    this.mResponse = response;
    switch (response.statusCode) {
      case 200:
        this.mLoaders = (response as IMCDataOkResponse).contentLoaders;
        MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Response status 200. Loaders initialized with count: ${this.mLoaders?.length}.`);
        break;
      case 206:
        this.mLoaders = (response as IMCDataPartialContentResponse).contentLoaders;
        MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Response status 206. Loaders initialized with count: ${this.mLoaders?.length}.`);
        break;
    }

    if ( this.mAborted ) {
      this.clear(this.mError); // 这里需要清理请求到的 loaders;
      throw this.mError!;
    }

    Promise.resolve().then(() => this.prepareNextLoader());
  }

  private onError(error?: Error): void {
    if ( this.isCompleted ) {
      return;
    }

    this.abort(error);
  }

  private prepareNextLoader(): void {
    if ( this.isCompleted ) { // ended or aborted
      return;
    }

    const loaders = this.mLoaders;
    if ( loaders == undefined ) {
      return;
    }

    const currentLoader = this.mCurrentLoader;
    if ( currentLoader ) {
      currentLoader.off("stateChange");
      currentLoader.off("newDataReadable");
      this.mCurrentLoader = undefined;
    }

    const nextLoader = loaders.shift();
    if ( nextLoader == undefined ) {
      MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] All loaders processed.`);
      this.done();
      return;
    }

    this.mCurrentLoader = nextLoader;
    nextLoader.on("stateChange", (loader, state) => this.onLoaderStateChange(loader, state));
    nextLoader.on("newDataReadable", (loader) => this.onLoaderNewDataReadable(loader));
    nextLoader.prepare();
  }

  private onLoaderStateChange(loader: IMCMediaContentLoader, state: MCMediaContentLoaderState): void {
    if ( loader != this.mCurrentLoader ) return;
    switch (state) {
      case MCMediaContentLoaderState.Ready:
        if ( loader.readableLength > 0 ) this.onLoaderNewDataReadable(loader);
        break;
      case MCMediaContentLoaderState.Ended:
        this.prepareNextLoader();
        break;
      case MCMediaContentLoaderState.Aborted:
        MCLogger.error(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Loader aborted with error: ${loader.error?.message}`);
        this.onError(loader.error);
        break;
    }
  }

  private onLoaderNewDataReadable(loader: IMCMediaContentLoader): void {
    if ( loader != this.mCurrentLoader ) return;
    this.mOnNewDataReadable?.(this);
  }

  private generateResponseHeaders(dataResponse: IMCDataResponse): IMCHttpResponseHeaders {
    switch (dataResponse.statusCode) {
      case 200: {
        const okResponse = dataResponse as IMCDataOkResponse;
        const responseHeaders: IMCHttpOkResponseHeaders = {
          statusCode: 200,
          contentType: okResponse.contentType,
          chunked: okResponse.chunked,
          contentLength: okResponse.contentLength,
          byteRangeAccessSupported: okResponse.byteRangeAccessSupported,
        }
        return responseHeaders;
      }
      case 206: {
        const partialResponse = dataResponse as IMCDataPartialContentResponse;
        const responseHeaders: IMCHttpPartialContentResponseHeaders = {
          statusCode: 206,
          contentType: partialResponse.contentType,
          contentRange: partialResponse.contentRange,
          totalLength: partialResponse.totalLength,
        };
        return responseHeaders;
      }
      default: {
        const responseHeaders: IMCHttpResponseHeaders = {
          statusCode: dataResponse.statusCode,
        }
        return responseHeaders;
      }
    }
  }
}