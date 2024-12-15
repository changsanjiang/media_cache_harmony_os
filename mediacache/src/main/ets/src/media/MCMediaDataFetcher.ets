import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCDataOkResponse, IMCDataPartialContentResponse, IMCDataResponse } from "../defines/IMCDataResponse";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCLogger from "../utils/MCLogger";
import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import { IMCMedia } from "../defines/IMCMedia";
import { IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders } from "../defines/IMCHttpResponseHeaders";
import MCConfigs from "../utils/MCConfigs";

export class MCMediaDataFetcher implements IMCDataFetcher {
  private mMedia: IMCMedia;
  private mClientId: number;
  private mRequest: IMCDataRequest;

  private mResponseReceiveCallback?: (fetcher: IMCDataFetcher, responseHeaders: IMCHttpResponseHeaders) => void | Promise<void> = undefined;
  private mDataReceiveCallback?: (fetcher: IMCDataFetcher, offset: number, data: ArrayBuffer) => void | Promise<void> = undefined;
  private mDataEndCallback?: (fetcher: IMCDataFetcher) => void = undefined;
  private mAbortedCallback?: (fetcher: IMCDataFetcher, error?: Error) => void = undefined;

  private mDataEnd = false;
  private mAborted = false;

  private mFetchAbortController?: MCAbortController = undefined;
  private mResponse?: IMCDataResponse = undefined;
  private mLoaders?: IMCMediaContentLoader[] = undefined;
  private mCurrentLoader?: IMCMediaContentLoader = undefined;

  private mOnMediaRemoveAllCachesBeforeCallback = (_: IMCMedia) => this.abort(new Error(`Media all contents will be removed.`));

  constructor(clientId: number, media: IMCMedia, request: IMCDataRequest) {
    this.mClientId = clientId;
    this.mMedia = media;
    this.mRequest = request;

    media.readwriteRetain();
    media.on('removeAllCachesBefore', this.mOnMediaRemoveAllCachesBeforeCallback);
  }

  get isAborted(): boolean {
    return this.mAborted;
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Starting prepare for request: ${JSON.stringify(this.mRequest)}}`);

    if (this.mAborted) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted.`);
      return;
    }

    this.mFetchAbortController = new MCAbortController();
    this.mMedia.fetch(this.mRequest, this.mFetchAbortController.signal).then((response) => {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Fetch completed successfully.`);
      this.mFetchAbortController = undefined;
      this.onResponse(response);
    }).catch((error: Error) => {
      MCLogger.error(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Fetch failed. Error: ${error.message}`);
      if ( this.mFetchAbortController ) this.mFetchAbortController = undefined;
      this.onError(error);
    });
  }

  private async onResponse(response: IMCDataResponse): Promise<void> {
    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Received response with status code: ${response.statusCode}`);

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
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Fetcher aborted before processing the response.`);
      this.clear();
      return;
    }

    if (this.mResponseReceiveCallback) {
      const responseHeaders = this.generateResponseHeaders(response);
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Invoking responseReceive callback.`);
      await this.mResponseReceiveCallback(this, responseHeaders);
    }

    if ( this.mAborted ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Fetcher aborted after responseReceive callback.`);
      return;
    }

    if ( this.mLoaders && this.mLoaders.length > 0 ) {
      this.prepareNextLoader();
    }
    else {
      MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] No loaders available. Marking fetcher as done.`);
      this.done();
    }
  }

  private prepareNextLoader(): void {
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Preparing next loader.`);

    if (this.mAborted) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare next loader as fetcher is aborted.`);
      return;
    }

    try {
      let loaders = this.mLoaders;

      if (!loaders) {
        throw new Error(`Loaders array is not initialized.`);
      }

      // 清理旧的 loader
      if (this.mCurrentLoader) {
        this.offLoaderEvents(this.mCurrentLoader);
        this.mCurrentLoader = undefined;
      }

      // 获取下一个loader
      const nextLoader = loaders.shift();
      if (!nextLoader) {
        MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] All loaders processed.`);
        this.done();
        return;
      }

      // 监听数据加载
      this.mCurrentLoader = nextLoader;
      MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Next loader prepared. Remaining loaders count: ${this.mLoaders!.length}`);
      nextLoader.on("dataLoad", async (_: IMCMediaContentLoader, offset: number, data: ArrayBuffer) => {
        if ( this.mAborted || !this.mDataReceiveCallback ) {
          MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Skipping dataLoad event as fetcher is aborted or callback is undefined.`);
          return;
        }

        MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Handling dataLoad event. Offset: ${offset}, Bytes: ${data.byteLength}.`);

        try {
          // 校验数据一致性
          if ( MCConfigs.dataValidator ) {
            MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Validating data. Offset: ${offset}, Bytes: ${data.byteLength}.`);
            const result = await MCConfigs.dataValidator(this.mRequest, offset, data);
            if ( !result ) {
              throw new Error(`Data validation failed at offset ${offset}. Data size: ${data.byteLength} bytes.`);
            }

            MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Data validation passed. Offset: ${offset}, Bytes: ${data.byteLength}.`);
          }

          // 数据解密
          if ( MCConfigs.dataDecryptHandler ) {
            MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Decrypting data. Offset: ${offset}, Bytes: ${data.byteLength}.`);
            await MCConfigs.dataDecryptHandler(this.mRequest, offset, data);
            MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Data decryption completed. Offset: ${offset}, Bytes: ${data.byteLength}.`);
          }

          await this.mDataReceiveCallback(this, offset, data);
          MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Data successfully processed by receive callback. Offset: ${offset}, Bytes: ${data.byteLength}.`);
        }
        catch (error) {
          MCLogger.error(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Error in dataReceive callback: ${error.message}`);
          this.onError(error);
          throw error as Error;
        }
      });
      nextLoader.on("dataEnd", (_: IMCMediaContentLoader) => this.prepareNextLoader());
      nextLoader.on("aborted", (_: IMCMediaContentLoader, error?: Error) => this.onError(error));
      nextLoader.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Error preparing next loader. ${error.message}`);
      this.onError(error);
      throw error as Error;
    }
  }

  private onError(error?: Error): void {
    if ( !this.mAborted ) {
      this.abort(error);
    }
    else {
      this.clear(error);
    }
  }

  private done() {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as done.`);

    this.mDataEnd = true;

    this.mMedia.readwriteRelease();
    this.mMedia.off('removeAllCachesBefore', this.mOnMediaRemoveAllCachesBeforeCallback);

    if ( this.mDataEndCallback )  {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Executing dataEnd callback.`);
      this.mDataEndCallback(this);
    }
  }

  async abort(error?: Error): Promise<void> {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    MCLogger.warn(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting fetcher${error ? ` due to error: ${error.message}` : ""}.`);

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as aborted. response: ${this.mResponse}, currentLoader: ${this.mCurrentLoader}, loaders.length: ${this.mLoaders?.length}`);

    this.mAborted = true;

    if ( this.mFetchAbortController ) {
      this.mFetchAbortController.abort(error);
      this.mFetchAbortController = undefined;
    }

    if ( this.mResponse ) {
      await this.clear(error);
    }

    this.mMedia.readwriteRelease();
    this.mMedia.off('removeAllCachesBefore', this.mOnMediaRemoveAllCachesBeforeCallback);

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private async clear(error?: Error): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Starting clear with error: ${error?.message || "None"}. response: ${this.mResponse}, currentLoader: ${this.mCurrentLoader}, loaders.length: ${this.mLoaders?.length}`);

    const loader = this.mCurrentLoader;
    const loaders = this.mLoaders;

    if ( loader ) {
      this.mCurrentLoader = undefined;
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting active loader.`);
      this.offLoaderEvents(loader);
      try { await loader.abort(error); } catch (_) { }
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Active loader cleared.`);
    }

    if ( loaders ) {
      this.mLoaders = undefined;
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting remaining loaders. size: ${this.mLoaders!.length}.`);
      loaders.forEach(async (loader) => {
        this.offLoaderEvents(loader);
        try { await loader.abort(error); } catch (_) { }
      });
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Remaining loaders cleared.`);
    }
  }

  private offLoaderEvents(loader: IMCMediaContentLoader) {
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Clearing loader event listeners.`);

    loader.off('dataLoad');
    loader.off('dataEnd');
    loader.off('aborted');
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

  on(event: "responseReceive" | "dataReceive" | "dataEnd" | "aborted", callback: Function): void {
    switch (event) {
      case 'responseReceive':
        this.mResponseReceiveCallback = callback as (fetcher: IMCDataFetcher, responseHeaders: IMCHttpResponseHeaders) => void | Promise<void>;
        break;
      case 'dataReceive':
        this.mDataReceiveCallback = callback as (fetcher: IMCDataFetcher, offset: number, data: ArrayBuffer) => void | Promise<void>;
        break;
      case 'dataEnd':
        this.mDataEndCallback = callback as (fetcher: IMCDataFetcher) => void;
        break;
      case 'aborted':
        this.mAbortedCallback = callback as (fetcher: IMCDataFetcher, error?: Error) => void;
        break;
    }
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Event listener for '${event}' registered.`);
  }

  off(event: "responseReceive" | "dataReceive" | "dataEnd" | "aborted"): void {
    switch (event) {
      case 'responseReceive':
        this.mResponseReceiveCallback = undefined;
        break;
      case 'dataReceive':
        this.mDataReceiveCallback = undefined;
        break;
      case 'dataEnd':
        this.mDataEndCallback = undefined;
        break;
      case 'aborted':
        this.mAbortedCallback = undefined;
        break;
    }
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Event listener for '${event}' unregistered.`);
  }
}