import { ArkTSUtils } from "@kit.ArkTS";
import { IMCAssetDataReader } from "../common/IMCAssetDataReader";
import MCAssetManager from "../asset/MCAssetManager";
import MCLogger from "../utils/MCLogger";
import { IMCHttpRequest } from "../common/IMCHttpRequest";
import { IMCHttpResponse } from "../common/IMCHttpResponse";
import { IMCAssetDataOkResponse,
  IMCAssetDataPartialContentResponse,
  IMCAssetDataResponse, MCAssetDataResponseType } from "../common/IMCAssetDataResponse";

export class MCHttpResponse implements IMCHttpResponse {
  private mClientId: number;
  /// headers是否已发送给客户端;
  private mHeadersSent = false;
  private mDataReader?: IMCAssetDataReader = undefined;
  private mNewDataCallback?: (response: IMCHttpResponse) => void = undefined;
  private mAbortedCallback?: (response: IMCHttpResponse, error?: Error) => void = undefined;
  private mAborted = false;
  private mDone = false;
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();

  constructor(clientId: number) {
    this.mClientId = clientId;
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse][clientId: ${this.mClientId}] New Response instance created.`);
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
      if (this.mDataReader) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpResponse][clientId: ${this.mClientId}] A request is already being processed. Unable to prepare response.`);
        throw new Error("A request is already being processed.");
      }

      MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse][clientId: ${this.mClientId}] Preparing data reader for request: ${JSON.stringify(proxyRequest)}`);

      this.mDataReader = MCAssetManager.createDataReader(proxyRequest);
      this.mDataReader.on('responseReady', (_) => this.mLock.lockAsync(() => this.mNewDataCallback).then((callback) => callback?.(this)));
      this.mDataReader.on('newDataReadable', (_) => this.mLock.lockAsync(() => this.mNewDataCallback).then((callback) => callback?.(this)));
      this.mDataReader.on('aborted', (_, error) => this.abort(error));
      await this.mDataReader?.prepare();
      MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse][clientId: ${this.mClientId}] Data reader prepared successfully.`);
    });
  }

  readData(): Promise<string | ArrayBuffer | undefined> {
    return this.mLock.lockAsync(async () => {
      if ( this.mDone || this.mAborted ) {
        MCLogger.log(MCLogger.LogLevel.WARN, `[MCHttpResponse][clientId: ${this.mClientId}] Attempt to read data after response completion or abortion.`);
        return undefined;
      }

      const reader = this.mDataReader;
      if ( !reader ) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpResponse][clientId: ${this.mClientId}] No data reader found while attempting to read data.`);
        return undefined;
      }

      // 先向客户端发送响应头消息
      if ( !this.mHeadersSent ) {
        MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCHttpResponse][clientId: ${this.mClientId}] Generating response headers for data response.`);
        const responseHeaders = this.generateResponseHeaders(await reader.response);
        if ( responseHeaders ) {
          this.mHeadersSent = true;
          MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse][clientId: ${this.mClientId}] Headers sent to client: ${JSON.stringify(responseHeaders)}`);
          this.mDone = await reader.isDone;
          if ( this.mDone ) {
            reader.off('responseReady');
            reader.off('newDataReadable');
            reader.off('aborted');
            this.mDataReader = undefined;
          }
        }
        return responseHeaders;
      }

      // 读取可读数据
      const readableLength = await reader.readableLength;
      if ( readableLength > 0 ) {
        const data = await reader.readData(4 * 1024 * 1024);
        this.mDone = await reader.isDone;
        if ( this.mDone ) {
          reader.off('responseReady');
          reader.off('newDataReadable');
          reader.off('aborted');
          this.mDataReader = undefined;
        }
        MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCHttpResponse][clientId: ${this.mClientId}] Data chunk read (${data?.byteLength || 0} bytes), Done=${this.mDone}`);
        return data;
      }

      MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCHttpResponse][clientId: ${this.mClientId}] No data available for reading.`);
      return undefined;
    })
  }

  abort(error?: Error): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( this.mAborted || this.mDone ) {
        MCLogger.log(MCLogger.LogLevel.WARN, `[MCHttpResponse][clientId: ${this.mClientId}] Abort called after response completion or previous abortion.`);
        return undefined;
      }

      this.mAborted = true;

      if ( this.mDataReader ) {
        this.mDataReader?.off('newDataReadable');
        this.mDataReader?.off('aborted');
        this.mDataReader?.abort(error);
        this.mDataReader = undefined;
      }

      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpResponse][clientId: ${this.mClientId}] Response aborted${error ? ` due to error: ${error.message}` : ""}.`);

      return this.mAbortedCallback;
    }).then((callback) => callback?.(this, error));
  }

  on(event: string, callback: Object): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( event === 'newDataAvailable' ) {
        if (this.mNewDataCallback) {
          MCLogger.log(MCLogger.LogLevel.WARN, `[MCHttpResponse][clientId: ${this.mClientId}] Event listener for 'newDataAvailable' is already registered.`);
        }
        this.mNewDataCallback = callback as (reader: IMCHttpResponse) => void;
      }
      else if ( event === 'aborted' ) {
        if (this.mAbortedCallback) {
          MCLogger.log(MCLogger.LogLevel.WARN, `[MCHttpResponse][clientId: ${this.mClientId}] Event listener for '${event}' is being replaced.`);
        }
        this.mAbortedCallback = callback as (reader: IMCHttpResponse, error?: Error) => void;
      }
      MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse][clientId: ${this.mClientId}] Event listener for '${event}' registered.`);
    });
  }

  off(event: string): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( event === 'newDataAvailable' ) {
        this.mNewDataCallback = undefined;
      }
      else if ( event === 'aborted' ) {
        this.mAbortedCallback = undefined;
      }
      MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse][clientId: ${this.mClientId}] Event listener for '${event}' unregistered.`);
    });
  }

  private generateResponseHeaders(dataResponse?: IMCAssetDataResponse): string | undefined {
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
      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpResponse][clientId: ${this.mClientId}] Cannot generate headers: Response data is undefined.`);
      return undefined;
    }

    const currentDate = new Date().toUTCString();
    switch (dataResponse.type) {
      case MCAssetDataResponseType.OK: {
        const okResponse = dataResponse as IMCAssetDataOkResponse;
        return (
          `HTTP/1.1 200 OK\r\n` +
            `Content-Type: ${okResponse.contentType}\r\n` +
            `Content-Length: ${okResponse.contentLength}\r\n` +
            `Accept-Ranges: ${okResponse.byteRangeAccessSupported ? "bytes" : "none"}\r\n` +
            `Date: ${currentDate}\r\n` +
            `\r\n`
        );
      }
      case MCAssetDataResponseType.PARTIAL_CONTENT: {
        const partialResponse = dataResponse as IMCAssetDataPartialContentResponse;
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
      case MCAssetDataResponseType.BAD_REQUEST:
        return `HTTP/1.1 400 Bad Request\r\nDate: ${currentDate}\r\n\r\n`;
      default: {
        if ( dataResponse.type !== MCAssetDataResponseType.INTERNAL_ERROR ) {
          MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpResponse][clientId: ${this.mClientId}] Unsupported response type: ${dataResponse.type}`);
        }
        return `HTTP/1.1 500 Internal Server Error\r\nDate: ${currentDate}\r\n\r\n`;
      }
    }
  }
}