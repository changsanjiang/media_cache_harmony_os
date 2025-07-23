import MCLogger from '../utils/MCLogger';
import { IMCHttpRequest } from '../defines/IMCHttpRequest';
import { IMCHttpResponse } from '../defines/IMCHttpResponse';
import { MCLogModule } from '../defines/MCLogModule';
import { MCAssetDataFetcher } from '../asset/MCAssetDataFetcher';
import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import MCAssetManager from '../asset/MCAssetManager';
import {
  IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders
} from '../defines/IMCHttpResponseHeaders';
import { buffer, util } from '@kit.ArkTS';
import MCURL from '../utils/MCURL';

export class MCHttpResponse implements IMCHttpResponse {
  private mClientId: number;
  private mRequest: IMCHttpRequest
  private mFetcher?: IMCDataFetcher = undefined;
  private mChunked = false;
  private mChunkReadEnd = false; // chunked 结束块是否已通过 read 读取

  private mAborted = false;
  private mDataEnd = false;
  private mError?: Error = undefined;

  private mOnNewDataReadable?: (response: IMCHttpResponse) => void = undefined;
  private mOnAborted?: (response: IMCHttpResponse, error: Error) => void = undefined;

  constructor(clientId: number, request: IMCHttpRequest) {
    this.mClientId = clientId;
    this.mRequest = request;
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${clientId}] Instance created for URL: ${MCURL.parseUrl(request.requestTarget)}, request: ${JSON.stringify(request)}.`);
  }

  get isReady(): boolean {
    return this.mFetcher?.isReady ?? false;
  }

  get isCompleted(): boolean {
    return this.mAborted || this.isDone;
  }

  get isDone(): boolean {
    return this.mDataEnd && (!this.mChunked || this.mChunkReadEnd);
  }

  async prepare(): Promise<string> {
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing response`);
    try {
      const asset = await MCAssetManager.getAssetByRequestTarget(this.mRequest.requestTarget);
      if ( this.mAborted ) {
        throw this.mError!;
      }

      this.mFetcher = new MCAssetDataFetcher(this.mClientId, asset, {
        requestTarget: this.mRequest.requestTarget,
        headers: this.mRequest.headers
      });
      this.mFetcher.on('newDataReadable', () => this.onNewDataReadable());
      this.mFetcher.on('aborted', (_, error) => this.onError(error));

      const responseHeaders = await this.mFetcher.prepare();
      if ( this.mAborted ) {
        throw this.mError!;
      }

      this.mChunked = responseHeaders.statusCode === 200 && (responseHeaders as IMCHttpOkResponseHeaders).chunked === true;
      const rawHeaders = this.generateResponseHeaders(responseHeaders);

      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Finished preparation. Chunked: ${this.mChunked}, RawHeaders: ${rawHeaders}`);
      return rawHeaders;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Error during response preparation: ${error.message}. Stack trace: ${error.stack}`);
      this.onError(error);
      throw error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Starting read data`);

    const fetcher = this.mFetcher;
    if ( fetcher == undefined ) return undefined;
    const data = await fetcher.read(capacity);
    if ( data ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Finished read data, size: ${data.byteLength} bytes, offset: ${fetcher.offset}, readable: ${fetcher.readableLength} bytes`);

      if ( fetcher.isDataEnd ) {
        this.mDataEnd = true;
      }

      if ( this.mChunked ) {
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
        return chunkedData;
      }
    }
    // no data read
    else {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] No data read in current attempt`);

      if ( this.mDataEnd && this.mChunked && !this.mChunkReadEnd ) {
        MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Chunk readed end`);

        this.mChunkReadEnd = true;
        return buffer.from('0\r\n\r\n', 'utf-8').buffer;
      }
    }
    return data;
  }

  abort(error?: Error | undefined): void {
    if ( this.isCompleted ) {
      return;
    }

    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Aborting MCHttpResponse${error ? ` due to error: ${error.message}` : ''}. Stack trace: ${error?.stack || 'none'}`);

    this.mAborted = true;
    this.mError = error ?? new Error('Response was aborted');

    const fetcher = this.mFetcher;
    if ( fetcher ) {
      this.mFetcher = undefined;
      fetcher.off('newDataReadable');
      fetcher.off('aborted');
      if ( !fetcher.isCompleted ) fetcher.abort(this.mError);
    }

    setTimeout(() => {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${this.mError?.message}.`);
      this.mOnAborted?.(this, this.mError!);
    });
  }

  on(event: "newDataReadable", callback: (response: IMCHttpResponse) => void): void;
  on(event: "aborted", callback: (response: IMCHttpResponse, error: Error) => void): void;
  on(event: string, callback: Object): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = callback as (response: IMCHttpResponse) => void;
        break;
      case 'aborted':
        this.mOnAborted = callback as (response: IMCHttpResponse, error: Error) => void;
        break;
    }
  }

  off(event: "newDataReadable"): void;
  off(event: "aborted"): void;
  off(event: string): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = undefined;
        break;
      case 'aborted':
        this.mOnAborted = undefined;
        break;
    }
  }

  private onNewDataReadable(): void {
    this.mOnNewDataReadable?.(this);
  }

  private onError(error?: Error): void {
    if ( this.isCompleted ) {
      return;
    }

    this.abort(error);
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
}