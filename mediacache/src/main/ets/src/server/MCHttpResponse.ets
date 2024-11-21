import { ArkTSUtils } from "@kit.ArkTS";
import { IMCDataReader } from "../common/IMCDataReader";
import MCAssetManager from "../asset/MCAssetManager";
import MCLogger from "../utils/MCLogger";
import { IMCHttpRequest } from "../common/IMCHttpRequest";

export interface IMCHttpResponse {
  readonly isDone: Promise<boolean>;
  prepare(proxyRequest: IMCHttpRequest): Promise<void>
  readData(): Promise<string | ArrayBuffer | undefined>;
  abort(error?: Error): Promise<void>;
  on(event: 'newDataAvailable', callback: (response: IMCHttpResponse) => void): Promise<void>;
  off(event: 'newDataAvailable'): Promise<void>;
}

export class MCHttpResponse implements IMCHttpResponse {
  /// headers是否已发送给客户端;
  private mHeadersSent = false;
  private mDataReader?: IMCDataReader = undefined;
  private mNewDataCallback?: (response: IMCHttpResponse) => void = undefined;
  private mAborted = false;
  private mDone = false;
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();

  get isDone(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mDone);
  }

  prepare(proxyRequest: IMCHttpRequest): Promise<void> {
    return this.mLock.lockAsync(() => {
      if (this.mDataReader) {
        throw new Error("A request is already being processed.");
      }

      MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse] Preparing data reader for request: Method=${proxyRequest.method}, Target=${proxyRequest.requestTarget}`);

      this.mDataReader = MCAssetManager.createDataReader(proxyRequest);
      this.mDataReader.on('newDataReadable', (_) => this.mLock.lockAsync(() => this.mNewDataCallback).then((callback) => callback?.(this)));
    });
  }

  readData(): Promise<string | ArrayBuffer | undefined> {
    return this.mLock.lockAsync(async () => {
      if ( this.mDone || this.mAborted ) {
        MCLogger.log(MCLogger.LogLevel.WARN, `[MCHttpResponse] Attempt to read data after response completion or abortion.`);
        return undefined;
      }

      const reader = this.mDataReader;
      if ( !reader ) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpResponse] No data reader found while attempting to read data.`);
        return undefined;
      }

      // 先向客户端发送响应头消息
      if ( !this.mHeadersSent ) {
        // https://datatracker.ietf.org/doc/html/rfc9110#name-example-message-exchange
        //
        // HTTP/1.1 200 OK
        // Date: Mon, 27 Jul 2009 12:28:53 GMT
        // Server: Apache
        // Last-Modified: Wed, 22 Jul 2009 19:15:56 GMT
        // ETag: "34aa387-d-1568eb00"
        // Accept-Ranges: bytes
        // Content-Length: 51
        // Vary: Accept-Encoding
        // Content-Type: text/plain
        //
        // Hello World! My content includes a trailing CRLF.

        // https://datatracker.ietf.org/doc/html/rfc9110#name-single-part
        //
        // HTTP/1.1 206 Partial Content
        // Date: Wed, 15 Nov 1995 06:25:24 GMT
        // Last-Modified: Wed, 15 Nov 1995 04:58:08 GMT
        // Content-Range: bytes 21010-47021/47022
        // Content-Length: 26012
        // Content-Type: image/gif
        //
        // ... 26012 bytes of partial image data ...
        //
        const responseHeaders = await reader.response;
        if ( responseHeaders ) {
          this.mHeadersSent = true;
          MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse] Headers sent to client: ${responseHeaders}`);
        }
        return responseHeaders;
      }

      // 读取可读数据
      const readableLength = await reader.readableLength;
      if ( readableLength > 0 ) {
        const data = await reader.readData(4 * 1024 * 1024);
        this.mDone = await reader.isDone;
        MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCHttpResponse] Data chunk read (${data?.byteLength || 0} bytes), Done=${this.mDone}`);
        return data;
      }

      MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCHttpResponse] No data available for reading.`);
      return undefined;
    })
  }

  abort(error?: Error): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( this.mAborted || this.mDone ) {
        MCLogger.log(MCLogger.LogLevel.WARN, `[MCHttpResponse] Abort called after response completion or previous abortion.`);
        return;
      }

      this.mAborted = true;
      this.mDataReader?.abort(error);
      this.mDataReader = undefined;

      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCHttpResponse] Response aborted${error ? ` due to error: ${error.message}` : ""}.`);
    });
  }

  on(event: "newDataAvailable", callback: (response: IMCHttpResponse) => void): Promise<void> {
    return this.mLock.lockAsync(() => {
      this.mNewDataCallback = callback;
      MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse] Event listener for '${event}' registered.`);
    });
  }

  off(event: 'newDataAvailable'): Promise<void> {
    return this.mLock.lockAsync(() => {
      this.mNewDataCallback = undefined;
      MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpResponse] Event listener for '${event}' unregistered.`);
    });
  }
}