import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCDataOkResponse, IMCDataPartialContentResponse, IMCDataResponse } from "../defines/IMCDataResponse";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCLogger from "../utils/MCLogger";
import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import { IMCMedia } from "../defines/IMCMedia";

export class MCMediaDataFetcher implements IMCDataFetcher {
  private mMedia: IMCMedia;
  private mClientId: number;
  private mRequest: IMCDataRequest;

  private mResponseReceiveCallback?: (fetcher: IMCDataFetcher, responseHeaders: string) => void | Promise<void> = undefined;
  private mDataReceiveCallback?: (fetcher: IMCDataFetcher, offset: number, data: ArrayBuffer) => void | Promise<void> = undefined;
  private mDataEndCallback?: (fetcher: IMCDataFetcher) => void = undefined;
  private mAbortedCallback?: (fetcher: IMCDataFetcher, error?: Error) => void = undefined;

  private mDataEnd = false;
  private mAborted = false;

  private mFetchAbortController?: MCAbortController = undefined;
  private mResponse?: IMCDataResponse = undefined;
  private mResponseHeaders?: string = undefined;
  private mLoaders?: IMCMediaContentLoader[] = undefined;
  private mCurrentLoader?: IMCMediaContentLoader = undefined;

  constructor(clientId: number, media: IMCMedia, request: IMCDataRequest) {
    this.mClientId = clientId;
    this.mMedia = media;
    this.mRequest = request;

    media.readwriteRetain();
  }

  async prepare(): Promise<void> {
    if (this.mAborted) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted.`);
      return;
    }

    this.mFetchAbortController = new MCAbortController();
    this.mMedia.fetch(this.mRequest, this.mFetchAbortController.signal).then((response) => {
      this.mFetchAbortController = undefined;
      this.onResponse(response);
    }).catch((error: Error) => {
      if ( this.mFetchAbortController ) this.mFetchAbortController = undefined;
      this.onError(error);
    });
  }

  private async onResponse(response: IMCDataResponse): Promise<void> {
    this.mResponse = response;
    switch (response.statusCode) {
      case 200:
        this.mLoaders = (response as IMCDataOkResponse).contentLoaders;
        break;
      case 206:
        this.mLoaders = (response as IMCDataPartialContentResponse).contentLoaders;
        break;
    }

    if ( this.mAborted ) {
      this.clear();
      return;
    }

    this.mResponseHeaders = this.generateResponseHeaders(response);
    if (this.mResponseReceiveCallback) {
      await this.mResponseReceiveCallback(this, this.mResponseHeaders);
    }

    if ( this.mAborted ) {
      return;
    }

    if ( this.mLoaders && this.mLoaders.length > 0 ) {
      this.prepareNextLoader();
    }
    else {
      this.done();
    }
  }

  private prepareNextLoader(): void {
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Attempting to prepare next loader.`);

    if (this.mAborted) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Attempted to prepare next loader, but the reader is either aborted or completed.`);
      return;
    }

    try {
      let loaders = this.mLoaders;

      if (!loaders) {
        throw new Error(`No loaders available to prepare.`);
      }

      // 清理旧的 loader
      if (this.mCurrentLoader) {
        this.offLoaderEvents(this.mCurrentLoader);
        this.mCurrentLoader = undefined;
      }

      // 获取下一个loader
      const nextLoader = loaders.shift();
      if (!nextLoader) {
        MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] All loaders completed.`);
        this.done();
        return;
      }

      // 监听数据加载
      this.mCurrentLoader = nextLoader;
      MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Preparing next loader.`);
      nextLoader.on("dataLoad", async (_: IMCMediaContentLoader, offset: number, data: ArrayBuffer) => {
        if ( this.mAborted || !this.mDataReceiveCallback ) {
          return;
        }
        try {
          await this.mDataReceiveCallback(this, offset, data);
        }
        catch (error) {
          this.onError(error);
          throw error as Error;
        }
      });
      nextLoader.on("dataEnd", (_: IMCMediaContentLoader) => this.prepareNextLoader());
      nextLoader.on("aborted", (_: IMCMediaContentLoader, error?: Error) => this.onError(error));
      nextLoader.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Failed to prepare next loader. Error: ${error.message}, stack: ${error.stack}`);
      this.abort(error);
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

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Marking reader as done.`);

    this.mDataEnd = true;

    this.mMedia.readwriteRelease();

    if ( this.mDataEndCallback )  {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Executing dataEnd callback.`);
      this.mDataEndCallback(this);
    }
  }

  async abort(error?: Error): Promise<void> {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    MCLogger.warn(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting MCMediaDataReader${error ? ` due to error: ${error.message}` : ""}.`);

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Marking reader as aborted. response: ${this.mResponse}, currentLoader: ${this.mCurrentLoader}, loaders.length: ${this.mLoaders?.length}`);

    this.mAborted = true;

    if ( this.mFetchAbortController ) {
      this.mFetchAbortController.abort(error);
      this.mFetchAbortController = undefined;
    }

    if ( this.mResponse ) {
      await this.clear(error);
    }

    this.mMedia.readwriteRelease();

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private async clear(error?: Error): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Starting clear with error: ${error?.message || "None"}. response: ${this.mResponse}, currentLoader: ${this.mCurrentLoader}, loaders.length: ${this.mLoaders?.length}`);

    const loader = this.mCurrentLoader;
    if ( loader ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting active loader.`);
      this.offLoaderEvents(loader);
      try { await loader.abort(error); } catch (_) { }
      this.mCurrentLoader = undefined;
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Active loader cleared.`);
    }

    if ( this.mLoaders ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting remaining loaders. size: ${this.mLoaders!.length}.`);
      this.mLoaders.forEach(async (loader) => {
        this.offLoaderEvents(loader);
        try { await loader.abort(error); } catch (_) { }
      });
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Remaining loaders cleared.`);
      this.mLoaders = undefined;
    }
  }

  private offLoaderEvents(loader: IMCMediaContentLoader) {
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Clearing loader event listeners.`);

    loader.off('dataLoad');
    loader.off('dataEnd');
    loader.off('aborted');
  }

  private generateResponseHeaders(dataResponse: IMCDataResponse): string {
    // https://datatracker.ietf.org/doc/html/rfc9110#name-example-message-exchange
    //
    // HTTP/1.1 200 OK
    // Accept-Ranges: bytes
    // Content-Length: 51
    // Content-Type: text/plain
    //
    // Hello World! My content includes a trailing CRLF.
    //

    // https://datatracker.ietf.org/doc/html/rfc9110#name-single-part
    //
    // HTTP/1.1 206 Partial Content
    // Content-Range: bytes 21010-47021/47022
    // Content-Length: 26012
    // Content-Type: image/gif
    //
    // ... 26012 bytes of partial image data ...
    //

    // HTTP/1.1 400 Bad Request
    //

    // HTTP/1.1 500 Internal Server Error
    //

    const currentDate = new Date().toUTCString();
    switch (dataResponse.statusCode) {
      case 200: {
        const okResponse = dataResponse as IMCDataOkResponse;
        return (
          `HTTP/1.1 200 OK\r\n` +
            `Content-Type: ${okResponse.contentType}\r\n` +
            (okResponse.contentLength ? `Content-Length: ${okResponse.contentLength}\r\n` : '')  +
            (okResponse.byteRangeAccessSupported ? `Accept-Ranges: bytes\r\n` : '') +
            `Date: ${currentDate}\r\n` +
            `\r\n`
        )
      }
      case 206: {
        const partialResponse = dataResponse as IMCDataPartialContentResponse;
        return (
          `HTTP/1.1 206 Partial Content\r\n` +
            `Content-Range: bytes ${partialResponse.contentRange.location}-${partialResponse.contentRange.max - 1}/${partialResponse.totalLength}\r\n` +
            `Content-Type: ${partialResponse.contentType}\r\n` +
            `Content-Length: ${partialResponse.contentRange.length}\r\n` +
            `Accept-Ranges: bytes\r\n` +
            `Date: ${currentDate}\r\n` +
            `\r\n`
        );
      }
      case 400:
        return `HTTP/1.1 400 Bad Request\r\nDate: ${currentDate}\r\n\r\n`;
      default: {
        if ( dataResponse.statusCode !== 500 ) {
          MCLogger.warn(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Unsupported response with status code: ${dataResponse.statusCode}`);
        }
        return `HTTP/1.1 500 Internal Server Error\r\nDate: ${currentDate}\r\n\r\n`;
      }
    }
  }

  on(event: "responseReceive" | "dataReceive" | "dataEnd" | "aborted", callback: Function): void {
    switch (event) {
      case 'responseReceive':
        this.mResponseReceiveCallback = callback as (fetcher: IMCDataFetcher, responseHeaders: string) => void | Promise<void>;
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
  }
}