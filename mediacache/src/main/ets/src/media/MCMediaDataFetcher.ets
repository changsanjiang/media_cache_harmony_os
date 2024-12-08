import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCDataOkResponse, IMCDataPartialContentResponse, IMCDataResponse } from "../defines/IMCDataResponse";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCLogger from "../utils/MCLogger";
import { IMCDataFetcher } from "./IMCDataFetcher";
import { MCMedia } from "./MCMedia";

export class MCMediaDataFetcher implements IMCDataFetcher {
  private mMedia: MCMedia;
  private mClientId: number;
  private mProxyRequest: IMCDataRequest;

  private mResponseReceiveCallback?: (reader: IMCDataFetcher, responseHeaders: string) => void | Promise<void> = undefined;
  private mDataReceiveCallback?: (reader: IMCDataFetcher, data: ArrayBuffer) => void | Promise<void> = undefined;
  private mDataEndCallback?: (reader: IMCDataFetcher) => void = undefined;
  private mAbortedCallback?: (reader: IMCDataFetcher, error?: Error) => void = undefined;

  private mReading = false;
  private mDataEnd = false;
  private mAborted = false;

  private mFetchAbortController?: MCAbortController = undefined;
  private mResponse?: IMCDataResponse = undefined;
  private mResponseHeaders?: string = undefined;
  private mLoaders?: IMCMediaContentLoader[] = undefined;
  private mCurrentLoader?: IMCMediaContentLoader = undefined;

  constructor(clientId: number, media: MCMedia, proxyRequest: IMCDataRequest) {
    this.mClientId = clientId;
    this.mMedia = media;
    this.mProxyRequest = proxyRequest;
  }

  async prepare(): Promise<void> {
    if (this.mAborted) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted.`);
      return;
    }

    this.mFetchAbortController = new MCAbortController();
    this.mMedia.fetch(this.mProxyRequest, this.mFetchAbortController.signal).then((response) => {
      this.mFetchAbortController = undefined;
      this.onResponse(response);
    }).catch((error: Error) => {
      this.mFetchAbortController = undefined;
      this.abort(error);
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

  private async prepareNextLoader(): Promise<void> {
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
        if (!this.mCurrentLoader.isDone) {
          throw new Error(`Current loader is not done yet.`);
        }
        MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Clearing completed loader.`);
        this.offLoaderEvents(this.mCurrentLoader);
        this.mCurrentLoader = undefined;
      }

      const nextLoader = loaders.shift();
      if (!nextLoader) {
        MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] All loaders completed.`);
        this.done();
        return;
      }

      this.mCurrentLoader = nextLoader;
      MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Preparing next loader.`);

      nextLoader.on("newDataReadable", (loader: IMCMediaContentLoader) => {
        MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] New data readable event received for loader.`);
        this.onNewDataReadable(loader);
      });

      nextLoader.on("aborted", (_: IMCMediaContentLoader, error?: Error) => {
        MCLogger.error(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Loader aborted. Error: ${error?.message || "None"}`);
        this.abort(error);
      });

      nextLoader.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Failed to prepare next loader. Error: ${error.message}, stack: ${error.stack}`);
      this.abort(error);
      throw error as Error;
    }
  }

  private async onNewDataReadable(loader: IMCMediaContentLoader): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Starting onNewDataReadable: Aborted=${this.mAborted}, Done=${this.mDataEnd}, Reading=${this.mReading}.`);

    if ( this.mAborted || this.mDataEnd || this.mReading ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Skipping onNewDataReadable due to state: Aborted=${this.mAborted}, Done=${this.mDataEnd}, Reading=${this.mReading}.`);
      return;
    }

    if ( loader != this.mCurrentLoader ) {
      return;
    }

    this.mReading = true;
    try {
      while (!this.mAborted && !loader.isDone) {
        const buffer = await loader.readData();
        if ( !buffer || !this.mDataReceiveCallback ) {
          MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Data cannot be sent: BufferExist=${!!buffer}, CallbackExist=${!!this.mDataReceiveCallback}.`);
          break;
        }
        await this.mDataReceiveCallback(this, buffer);
        MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Sent data successfully: ${buffer.byteLength} bytes.`);
      }
      this.mReading = false;

      if ( !this.mAborted && loader.isDone ) {
        this.prepareNextLoader();
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Error during data read: ${error.message}`);
      this.mReading = false;
      this.abort(error as Error);
      throw error as Error;
    }
  }

  private done() {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Marking reader as done.`);

    this.mDataEnd = true;

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

    MCLogger.info(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Marking reader as aborted.`);

    this.mAborted = true;

    if ( this.mFetchAbortController ) {
      this.mFetchAbortController.abort(error);
      this.mFetchAbortController = undefined;
    }

    if ( this.mResponse ) {
      this.clear(error);
    }

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private clear(error?: Error) {
    const loader = this.mCurrentLoader;
    if ( loader ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting active loader.`);
      loader.abort(error);
      this.offLoaderEvents(loader);
      this.mCurrentLoader = undefined;
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Active loader cleared.`);
    }

    if ( this.mLoaders ) {
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Aborting remaining loaders. size: ${this.mLoaders!.length}.`);
      this.mLoaders.forEach((loader) => {
        this.offLoaderEvents(loader);
        loader.abort(error);
      });
      MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Remaining loaders cleared.`);
      this.mLoaders = undefined;
    }
  }

  private offLoaderEvents(loader: IMCMediaContentLoader) {
    MCLogger.debug(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Clearing loader event listeners.`);

    loader.off('newDataReadable');
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
        this.mResponseReceiveCallback = callback as (reader: IMCDataFetcher, responseHeaders: string) => void | Promise<void>;
        break;
      case 'dataReceive':
        this.mDataReceiveCallback = callback as (reader: IMCDataFetcher, data: ArrayBuffer) => void | Promise<void>;
        break;
      case 'dataEnd':
        this.mDataEndCallback = callback as (reader: IMCDataFetcher) => void;
        break;
      case 'aborted':
        this.mAbortedCallback = callback as (reader: IMCDataFetcher, error?: Error) => void;
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