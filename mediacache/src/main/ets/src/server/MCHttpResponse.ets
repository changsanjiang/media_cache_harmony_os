import { ArkTSUtils } from "@kit.ArkTS";
import { IMCMediaDataReader } from "../defines/IMCMediaDataReader";
import MCLogger from "../utils/MCLogger";
import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCHttpResponse } from "../defines/IMCHttpResponse";
import { IMCMediaDataOkResponse,
  IMCMediaDataPartialContentResponse,
  IMCMediaDataResponse, MCMediaDataResponseType } from "../defines/IMCMediaDataResponse";
import { MCMediaDataReader } from "../asset/MCMediaDataReader";
import { MCLogModule } from "../defines/MCLogModule";

export class MCHttpResponse implements IMCHttpResponse {
  private mClientId: number;
  /// headers是否已发送给客户端;
  private mHeadersSent = false;
  private mDataReader?: IMCMediaDataReader = undefined;
  private mNewDataCallback?: (response: IMCHttpResponse) => void = undefined;
  private mAbortedCallback?: (response: IMCHttpResponse, error?: Error) => void = undefined;
  private mAborted = false;
  private mDone = false;
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();

  constructor(clientId: number) {
    this.mClientId = clientId;
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] New MCHttpResponse instance created.`);
  }

  get isDone(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mDone);
  }

  get isAborted(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAborted);
  }

  get isHeadersSent(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mHeadersSent);
  }

  prepare(proxyRequest: IMCHttpRequest): Promise<void> {
    return this.mLock.lockAsync(async () => {
      try {
        if (this.mDataReader) {
          throw new Error("A request is already being processed.");
        }

        MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing data reader for request: ${JSON.stringify(proxyRequest)}`);

        this.mDataReader = new MCMediaDataReader(this.mClientId, proxyRequest);
        this.mDataReader.on('responseReady', (_) => this.mLock.lockAsync(() => this.mNewDataCallback).then((callback) => callback?.(this)));
        this.mDataReader.on('newDataReadable', (_) => this.mLock.lockAsync(() => this.mNewDataCallback).then((callback) => callback?.(this)));
        this.mDataReader.on('aborted', (_, error) => this.abort(error));
        await this.mDataReader.prepare();
        MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Data reader prepared successfully.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Failed to prepare data reader: ${error.message}`);
        this.abortUnsafe(error as Error);
        throw error as Error;
      }
    });
  }

  readData(): Promise<string | ArrayBuffer | undefined> {
    return this.mLock.lockAsync(async () => {
      try {
        if ( this.mDone || this.mAborted ) {
          MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Attempt to read data after response completion or abortion.`);
          return undefined;
        }

        const reader = this.mDataReader;
        if ( !reader ) {
          MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] No data reader found while attempting to read data.`);
          return undefined;
        }

        // 先向客户端发送响应头消息
        if ( !this.mHeadersSent ) {
          MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Generating response headers for data response.`);
          const responseHeaders = this.generateResponseHeaders(await reader.response);
          if ( responseHeaders ) {
            this.mHeadersSent = true;
            MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Response headers sent to client: ${JSON.stringify(responseHeaders)}`);
            this.mDone = await reader.isDone;
            if ( this.mDone ) {
              this.clear();
            }
          }
          return responseHeaders;
        }

        // 读取可读数据
        const readableLength = await reader.readableLength;
        if ( readableLength > 0 ) {
          const bufferSize = Math.min(4 * 1024 * 1024, readableLength);
          const buffer = new ArrayBuffer(bufferSize);
          const length = await reader.readData(buffer);
          if (length > 0) {
            this.mDone = await reader.isDone;
            if ( this.mDone ) {
              this.clear();
            }
            MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Data chunk read (${length} bytes), Done=${this.mDone}`);
            return length === bufferSize ? buffer : buffer.slice(0, length);
          }
        }

        MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] No data available for reading.`);
        return undefined;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Error during data read: ${error.message}`);
        this.abortUnsafe(error as Error);
        throw error as Error;
      }
    })
  }

  abort(error?: Error): Promise<void> {
    return this.mLock.lockAsync(() => this.abortUnsafe(error));
  }

  on(event: 'newDataAvailable' | 'aborted', callback: Object): Promise<void> {
    return this.mLock.lockAsync(() => {
      switch (event) {
        case 'newDataAvailable': {
          if (this.mNewDataCallback) MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for 'newDataAvailable' is already registered.`);
          this.mNewDataCallback = callback as (reader: IMCHttpResponse) => void;
        }
          break;
        case 'aborted': {
          if (this.mAbortedCallback) MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' is being replaced.`);
          this.mAbortedCallback = callback as (reader: IMCHttpResponse, error?: Error) => void;
        }
          break;
      }
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' registered.`);
    });
  }

  off(event: 'newDataAvailable' | 'aborted'): Promise<void> {
    return this.mLock.lockAsync(() => {
      switch (event) {
        case 'newDataAvailable': {
          this.mNewDataCallback = undefined;
        }
          break;
        case 'aborted': {
          this.mAbortedCallback = undefined;
        }
          break;
      }
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' unregistered.`);
    });
  }

  private clear(shouldAborted: boolean = false, error?: Error) {
    if ( this.mDataReader ) {
      this.mDataReader.off('responseReady');
      this.mDataReader.off('newDataReadable');
      this.mDataReader.off('aborted');
      if ( shouldAborted ) this.mDataReader.abort(error);
      this.mDataReader = undefined;
    }
  }

  private abortUnsafe(error?: Error): void {
    if ( this.mAborted || this.mDone ) {
      MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Abort called after response completion or previous abortion.`);
      return undefined;
    }

    this.mAborted = true;

    this.clear(true, error);

    MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Response aborted${error ? ` due to error: ${error.message}` : ""}.`);

    Promise.resolve(this.mAbortedCallback).then((callback) => callback?.(this, error));
  }

  private generateResponseHeaders(dataResponse?: IMCMediaDataResponse): string | undefined {
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

    if (!dataResponse) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Cannot generate headers: Response data is undefined.`);
      return undefined;
    }

    const currentDate = new Date().toUTCString();
    switch (dataResponse.type) {
      case MCMediaDataResponseType.OK: {
        const okResponse = dataResponse as IMCMediaDataOkResponse;
        return (
          `HTTP/1.1 200 OK\r\n` +
            `Content-Type: ${okResponse.contentType}\r\n` +
            `Content-Length: ${okResponse.contentLength}\r\n` +
            `Accept-Ranges: ${okResponse.byteRangeAccessSupported ? "bytes" : "none"}\r\n` +
            `Date: ${currentDate}\r\n` +
            `\r\n`
        );
      }
      case MCMediaDataResponseType.PARTIAL_CONTENT: {
        const partialResponse = dataResponse as IMCMediaDataPartialContentResponse;
        return (
          `HTTP/1.1 206 Partial Content\r\n` +
            `Content-Range: bytes ${partialResponse.contentOffset}-${partialResponse.contentOffset + partialResponse.contentLength - 1}/${partialResponse.totalLength}\r\n` +
            `Content-Type: ${partialResponse.contentType}\r\n` +
            `Content-Length: ${partialResponse.contentLength}\r\n` +
            `Accept-Ranges: bytes\r\n` +
            `Date: ${currentDate}\r\n` +
            `\r\n`
        );
      }
      case MCMediaDataResponseType.BAD_REQUEST:
        return `HTTP/1.1 400 Bad Request\r\nDate: ${currentDate}\r\n\r\n`;
      default: {
        if ( dataResponse.type !== MCMediaDataResponseType.INTERNAL_ERROR ) {
          MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Unsupported response type: ${dataResponse.type}`);
        }
        return `HTTP/1.1 500 Internal Server Error\r\nDate: ${currentDate}\r\n\r\n`;
      }
    }
  }
}