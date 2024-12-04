import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContentLoader, MCMediaContentDecryptHandler } from "../defines/IMCMediaContentLoader";
import { IMCDataReader } from "../defines/IMCDataReader";
import {
  IMCDataOkResponse,
  IMCDataPartialContentResponse,
  IMCDataResponse } from "../defines/IMCDataResponse";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { MCLogModule } from "../defines/MCLogModule";
import { MCDataDecryptHandler } from "../defines/MCDataDecryptHandler";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { MCSerialQueue } from "../../../../../Index";

export class MCMediaDataReader implements IMCDataReader {
  private mClientId: number;
  private mProxyRequest: IMCDataRequest;
  private mDecrypt?: MCDataDecryptHandler;
  private mMedia: IMCMedia;
  private mResponse?: IMCDataResponse = undefined;
  private mResponseHeaders?: string = undefined;
  private mCurrentLoader?: IMCMediaContentLoader = undefined;
  private mDone = false;
  private mAborted = false;
  private mResponseReadyCallback?: (reader: IMCDataReader, responseHeaders: string) => void = undefined;
  private mNewDataReadableCallback?: (reader: IMCDataReader) => void = undefined;
  private mAbortedCallback?: (reader: IMCDataReader, error?: Error | undefined) => void = undefined;
  private mDoneCallback?: (reader: IMCDataReader) => void = undefined;
  private mSerialQueue = new MCSerialQueue();

  // 传入之前请先对 media 做一次 readwriteRetain, reader 内部会在操作结束后执行对应的 readwriteRelease;
  constructor(media: IMCMedia, clientId: number, proxyRequest: IMCDataRequest, decrypt?: MCDataDecryptHandler) {
    this.mClientId = clientId;
    this.mProxyRequest = proxyRequest;
    this.mMedia = media;
    this.mDecrypt = decrypt;
    MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Instance created with request target: ${proxyRequest.requestTarget}`);
  }

  get responseHeaders(): string | undefined {
    return this.mResponseHeaders;
  }
  get isDone(): boolean {
    return this.mDone;
  }
  get isAborted(): boolean {
    return this.mAborted;
  }

  // 获取media进行读取;
  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Starting preparation.`);
    try {
      if (this.mAborted) {
        MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Cannot prepare as the reader has been aborted.`);
        return;
      }

      this.mResponse = await this.mMedia.fetch(this.mProxyRequest);
      this.mResponseHeaders = this.generateResponseHeaders(this.mResponse);
      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Fetched data with response headers: ${this.mResponseHeaders}.`);

      if (this.mResponseReadyCallback) {
        MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Response prepared. Executing callback.`);
        this.mResponseReadyCallback(this, this.mResponseHeaders!);
      }

      switch (this.mResponse.statusCode) {
        case 200:
        case 206:
          this.prepareNextLoader();
          break;
        default:
          this.done();
          break;
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Failed to prepare media: ${error.message}, stack: ${error.stack}`);
      this.abort(error);
      throw error as Error;
    }
  }

  private async prepareNextLoader(): Promise<void> {
    MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Preparing next loader.`);

    if (this.mAborted || this.mDone) {
      MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Attempted to prepare next loader, but the reader is either aborted or completed.`);
      return;
    }

    try {
      let loaders: IMCMediaContentLoader[] | undefined = undefined;
      switch (this.mResponse!.statusCode) {
        case 200:
          loaders = (this.mResponse as IMCDataOkResponse).contentLoaders;
          break;
        case 206:
          loaders = (this.mResponse as IMCDataPartialContentResponse).contentLoaders;
          break;
      }

      if (!loaders) {
        throw new Error(`No loaders available to prepare.`);
      }

      if (loaders.length === 0) {
        this.done();
        return;
      }

      // 清理旧的 loader
      if (this.mCurrentLoader) {
        if ( !this.mCurrentLoader.isDone ) {
          throw new Error(`Current loader is not done yet.`);
        }
        MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Clearing completed loader.`);
        this.clearLoader(this.mCurrentLoader);
      }

      let nextIndex = this.mCurrentLoader ? (loaders.indexOf(this.mCurrentLoader) + 1) : 0;
      if ( nextIndex === loaders.length ) {
        MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] All loaders completed.`);
        this.done();
        return;
      }

      // 准备下一个loader
      const loader = loaders[nextIndex];
      this.mCurrentLoader = loader;
      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Preparing next loader at index ${nextIndex}.`);

      loader.on("prepared", (_: IMCMediaContentLoader, __: MCRange) => {
        MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader prepared event received for index ${nextIndex}.`);
        if ( this.mNewDataReadableCallback ) {
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Executing newDataReadable callback.`);
          this.mNewDataReadableCallback(this);
        }
      });

      loader.on("dataLoaded", (_: IMCMediaContentLoader, __: number) => {
        MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Data loaded event received for loader at index ${nextIndex}.`);
        if ( this.mNewDataReadableCallback ) {
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Executing newDataReadable callback.`);
          this.mNewDataReadableCallback(this);
        }
      });

      loader.on("aborted", (_: IMCMediaContentLoader, error?: Error) => {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader aborted at index ${nextIndex}. Error: ${error?.message || "None"}`);
        this.abort(error);
      });

      loader.on("done", () => {
        MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader at index ${nextIndex} has completed. Preparing the next loader.`);
        this.prepareNextLoader();
      });

      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader at index ${nextIndex} beging prepare.`);
      loader.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Failed to prepare next loader. Error: ${error.message}`);
      this.abort(error);
      throw error as Error;
    }
  }

  async readData(): Promise<ArrayBuffer | undefined> {
    return this.mSerialQueue.enqueue(async () => {
      if (this.mDone || this.mAborted || !this.mResponse || !this.mCurrentLoader) {
        MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Cannot read data. Status - Done: ${this.mDone}, Aborted: ${this.mAborted}, Response: ${this.mResponse}, CurrentLoader: ${this.mCurrentLoader}.`);
        return undefined;
      }

      const decrypt: MCMediaContentDecryptHandler | undefined = this.mDecrypt ? (offset: number, data: ArrayBuffer, len: number) => {
        return this.mDecrypt!(this.mProxyRequest, offset, data, len);
      } : undefined;

      try {
        const buffer = await this.mCurrentLoader.readData(decrypt);
        if ( buffer ) {
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader read ${buffer.byteLength} bytes of data.`);
        }
        else {
          MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] No data read.`);
        }
        return buffer;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Error during data read: ${error.message}`);
        throw error as Error;
      }
    });
  }

  // 跳转到当前可读范围的尾部，并返回跳转了的长度(readableLength);
  seekToEndOfReadableRange(): Promise<number> {
    return this.mSerialQueue.enqueue(async () => {
      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Starting seek to the end of the readable range.`);

      try {
        if (this.mDone || this.mAborted || !this.mResponse || !this.mCurrentLoader) {
          MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Seek operation aborted. Status - Done: ${this.mDone}, Aborted: ${this.mAborted}, Response: ${this.mResponse}, CurrentLoader: ${this.mCurrentLoader}.`);
          return 0;
        }
        const len = await this.mCurrentLoader.seekToEndOfReadableRange();

        if (len > 0) {
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader seeked ${len} bytes.`);
        }
        else {
          MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] No bytes skipped during seek. Loader may already be at the end of the readable range.`);
        }
        return len;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Error during seek operation: ${error.message}`);
        this.abort(error);
        throw error as Error;
      }
    });
  }

  private done() {
    if ( this.mAborted || this.mDone ) {
      return;
    }

    MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Marking reader as done.`);

    this.mDone = true;
    this.mMedia?.readwriteRelease();

    if ( this.mDoneCallback )  {
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Executing done callback.`);
      this.mDoneCallback(this);
    }
  }

  async abort(error?: Error | undefined): Promise<void> {
    if ( this.mAborted || this.mDone ) {
      return;
    }

    MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Aborting MCMediaDataReader${error ? ` due to error: ${error.message}` : ""}.`);

    this.mAborted = true;
    MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Reader marked as aborted.`);

    const loader = this.mCurrentLoader;
    if (loader) {
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Aborting active loader.`);
      loader.abort(error);
      this.clearLoader(loader);
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Active loader cleared.`);
    }

    this.mMedia.readwriteRelease();

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private clearLoader(loader: IMCMediaContentLoader) {
    MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Clearing loader event listeners.`);

    loader.off('prepared');
    loader.off('dataLoaded');
    loader.off('aborted');
    loader.off('done');
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
          MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Unsupported response with status code: ${dataResponse.statusCode}`);
        }
        return `HTTP/1.1 500 Internal Server Error\r\nDate: ${currentDate}\r\n\r\n`;
      }
    }
  }

  on(event: 'responseReady' | 'newDataReadable' | 'aborted' | 'done', callback: Object): void {
    MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Registering callback for event '${event}'.`);

    switch (event) {
      case "responseReady":
        this.mResponseReadyCallback = callback as (reader: IMCDataReader, responseHeaders: string) => void;
        break;
      case "newDataReadable":
        this.mNewDataReadableCallback = callback as (reader: IMCDataReader) => void;
        break;
      case "aborted":
        this.mAbortedCallback = callback as (reader: IMCDataReader, error?: Error | undefined) => void;
        break;
      case "done":
        this.mDoneCallback = callback as (reader: IMCDataReader) => void;
        break;
    }
  }

  off(event: 'responseReady' | 'newDataReadable' | 'aborted' | 'done'): void {
    MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Removing callback for event '${event}'.`);

    switch (event) {
      case "responseReady":
        this.mResponseReadyCallback = undefined;
        break;
      case "newDataReadable":
        this.mNewDataReadableCallback = undefined;
        break;
      case "aborted":
        this.mAbortedCallback = undefined;
        break;
      case "done":
        this.mDoneCallback = undefined;
        break;
    }
  }
}