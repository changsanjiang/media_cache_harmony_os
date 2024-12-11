import MCLogger from "../utils/MCLogger";
import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCHttpResponse } from "../defines/IMCHttpResponse";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAssetDataFetcher } from "../asset/MCAssetDataFetcher";
import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import MCAssetManager from "../asset/MCAssetManager";
import { IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders } from "../defines/IMCHttpResponseHeaders";
import { buffer, util } from "@kit.ArkTS";
import { MCURL } from "../../../../../Index";
import MCConfigs from "../utils/MCConfigs";

export class MCHttpResponse implements IMCHttpResponse {
  private mClientId: number;
  private mRequest: IMCHttpRequest
  private mFetcher?: IMCDataFetcher = undefined;
  private mHeadersReceiveCallback?: (response: IMCHttpResponse, headers: string) => void | Promise<void> = undefined;
  private mDataReceiveCallback?: (response: IMCHttpResponse, data: ArrayBuffer) => void | Promise<void> = undefined;
  private mAbortedCallback?: (response: IMCHttpResponse, error?: Error) => void | Promise<void> = undefined;
  private mDataEndCallback?: (response: IMCHttpResponse) => void | Promise<void> = undefined;
  private mChunked = false;
  private mAborted = false;
  private mDataEnd = false;

  constructor(clientId: number, request: IMCHttpRequest) {
    this.mClientId = clientId;
    this.mRequest = request;
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${clientId}] Instance created for URL: ${MCURL.parseUrl(request.requestTarget)}, request: ${JSON.stringify(request)}.`);
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing response.`);
    try {
      const asset = await MCAssetManager.getAssetBy(this.mRequest.requestTarget);
      this.mFetcher = new MCAssetDataFetcher(this.mClientId, asset, {
        requestTarget: this.mRequest.requestTarget,
        headers: this.mRequest.headers
      });
      this.mFetcher.on('responseReceive', async (_, responseHeaders: IMCHttpResponseHeaders) => this.onResponseReceive(responseHeaders));
      this.mFetcher.on('dataReceive', (_, offset, data) => this.onDataReceive(offset, data));
      this.mFetcher.on('dataEnd', (_) => this.onDataEnd());
      this.mFetcher.on('aborted', (_, error) => this.onError(error));
      this.mFetcher.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Error during asset reader preparation: ${error.message}`);
      this.onError(error);
      throw error as Error;
    }
  }

  private async onResponseReceive(responseHeaders: IMCHttpResponseHeaders): Promise<void> {
    if ( this.mAborted ) {
      return;
    }

    try {
      this.mChunked = responseHeaders.statusCode === 200 && (responseHeaders as IMCHttpOkResponseHeaders).chunked === true;
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing to send response headers.`);
      const rawStr = this.generateResponseHeaders(responseHeaders);
      await this.mHeadersReceiveCallback?.(this, rawStr);
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Response headers have been sent successfully. Headers are below: \n${rawStr}`);
    }
    catch (error) {
      this.onError(error);
      throw error as Error;
    }
  }

  private async onDataReceive(offset: number, data: ArrayBuffer): Promise<void> {
    if ( this.mAborted ) {
      return;
    }
    try {
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing to send response body data. Offset: ${offset}, Bytes: ${data.byteLength}.`);

      if ( !this.mChunked ) {
        await this.mDataReceiveCallback?.(this, data);
      }
      else {
        MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Processing chunked data. Offset: ${offset}, Bytes: ${data.byteLength}.`);

        // 拼接 chunk 数据：头部 + 数据 + 尾部
        //
        // 处理 chunked 编码的数据
        const uint8Array = new Uint8Array(data);
        // 获取块的大小（十六进制格式）
        const chunkSizeHex = uint8Array.byteLength.toString(16);
        // 编码块头部和尾部
        const encoder = new util.TextEncoder('utf-8');
        const chunkHeader = encoder.encodeInto(chunkSizeHex + '\r\n'); // 块大小
        const chunkFooter = encoder.encodeInto('\r\n'); // 块结束标记
        // 拼接 buffer: 头部 + 数据 + 尾部
        const chunkedData = new ArrayBuffer(chunkHeader.byteLength + data.byteLength + chunkFooter.byteLength);
        const dataView = new Uint8Array(chunkedData);
        dataView.set(chunkHeader, 0);
        dataView.set(new Uint8Array(data), chunkHeader.byteLength);
        dataView.set(chunkFooter, chunkHeader.byteLength + data.byteLength);
        await this.mDataReceiveCallback?.(this, chunkedData);
      }
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Sent ${this.mChunked ? 'chunked ' : ''}data successfully. Offset: ${offset}, Bytes: ${data.byteLength}.`);
    }
    catch (error) {
      this.onError(error);
      throw error as Error;
    }
  }

  private async onDataEnd(): Promise<void> {
    if ( this.mAborted || this.mDataEnd ) {
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Done ignored: Aborted=${this.mAborted}, Done=${this.mDataEnd}.`);
      return;
    }

    if (this.mChunked) {
      try {
        // 发送 chunked 数据的结束块
        await this.mDataReceiveCallback?.(this, buffer.from('0\r\n\r\n', 'utf-8').buffer);
        MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Sent chunked data end block.`);
      } catch (error) {
        MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Failed to send chunked data end block: ${error}`);
        this.onError(error);
        return;
      }
    }

    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Marking response as done.`);

    this.mDataEnd = true;
    this.clear();

    if ( this.mDataEndCallback ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Executing dataEnd callback.`);
      this.mDataEndCallback(this);
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

  async abort(error?: Error | undefined): Promise<void> {
    if ( this.mAborted || this.mDataEnd ) {
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Abort ignored: Aborted=${this.mAborted}, Done=${this.mDataEnd}.`);
      return;
    }

    MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Aborting MCHttpResponse${error ? ` due to error: ${error.message}` : ''}`);

    this.mAborted = true;

    await this.clear(error);

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || 'None'}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private async clear(error?: Error): Promise<void> {
    const fetcher = this.mFetcher;
    if ( fetcher ) {
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Clearing fetcher. Error: ${error?.message || 'none'}.`);
      this.mFetcher = undefined;
      fetcher.off('responseReceive');
      fetcher.off('dataReceive');
      fetcher.off('dataEnd');
      fetcher.off('aborted');

      if ( !fetcher.isAborted ) {
        try {
          MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Aborting fetcher.`);
          await fetcher.abort(error);
          MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Fetcher aborted successfully.`);
        } catch (abortError) {
          MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Failed to abort fetcher for request: ${this.mRequest}. Error: ${(abortError as Error)?.message || 'unknown'}`);
        }
      }
    }
  }

  private generateResponseHeaders(responseHeaders: IMCHttpResponseHeaders): string {
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
    switch (responseHeaders.statusCode) {
      case 200: {
        const okResponse = responseHeaders as IMCHttpOkResponseHeaders;
        return (
          `HTTP/1.1 200 OK\r\n` +
            `Content-Type: ${okResponse.contentType}\r\n` +
            (okResponse.chunked === true ? `Transfer-Encoding: chunked\r\n` : '') +
            (okResponse.contentLength ? `Content-Length: ${okResponse.contentLength}\r\n` : '')  +
            (okResponse.byteRangeAccessSupported === true ? `Accept-Ranges: bytes\r\n` : '') +
            `Date: ${currentDate}\r\n` +
            `\r\n`
        )
      }
      case 206: {
        const partialResponse = responseHeaders as IMCHttpPartialContentResponseHeaders;
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
        if ( responseHeaders.statusCode !== 500 ) {
          MCLogger.warn(MCLogModule.MCMediaDataFetcher, () => `[clientId: ${this.mClientId}] Unsupported response with status code: ${responseHeaders.statusCode}`);
        }
        return `HTTP/1.1 500 Internal Server Error\r\nDate: ${currentDate}\r\n\r\n`;
      }
    }
  }

  on(event: "headersReceive" | "dataReceive" | "dataEnd" | "aborted", callback: Function): void {
    switch (event) {
      case 'headersReceive':
        this.mHeadersReceiveCallback = callback as (response: IMCHttpResponse, headers: string) => void | Promise<void>;
        break;
      case 'dataReceive':
        this.mDataReceiveCallback = callback as (response: IMCHttpResponse, data: ArrayBuffer) => void | Promise<void>;
        break;
      case 'dataEnd':
        this.mDataEndCallback = callback as (response: IMCHttpResponse) => void | Promise<void>;
        break;
      case 'aborted':
        this.mAbortedCallback = callback as (response: IMCHttpResponse, error?: Error) => void | Promise<void>;
        break;
    }

    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' registered.`);
  }

  off(event: "headersReceive" | "dataReceive" | "dataEnd" | "aborted"): void {
    switch (event) {
      case 'headersReceive':
        this.mHeadersReceiveCallback = undefined;
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

    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' unregistered.`);
  }
}