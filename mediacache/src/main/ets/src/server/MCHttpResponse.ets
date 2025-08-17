import MCLogger from '../utils/MCLogger';
import { IMCHttpRequest } from '../defines/IMCHttpRequest';
import { IMCHttpResponse } from '../defines/IMCHttpResponse';
import { MCLogModule } from '../defines/MCLogModule';
import { MCAssetDataFetcher } from '../asset/MCAssetDataFetcher';
import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { MCAssetManager } from '../asset/MCAssetManager';
import {
  IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders
} from '../defines/IMCHttpResponseHeaders';
import { buffer, util } from '@kit.ArkTS';
import { MCProxyURLUtils } from '../utils/MCProxyURLUtils';

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
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${clientId}] Created response for request: ${JSON.stringify(request)}. URL: ${MCProxyURLUtils.parseTargetUrl(request.requestTarget)}`);
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
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Starting preparation for request: ${JSON.stringify(this.mRequest)}`);
    try {
      const asset = await MCAssetManager.getInstance().getAssetByProxyPath(this.mRequest.requestTarget);
      if ( this.mAborted ) {
        MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Cannot prepare as the response has been aborted`);
        throw this.mError!;
      }

      this.mFetcher = new MCAssetDataFetcher(this.mClientId, asset, {
        requestTarget: this.mRequest.requestTarget,
        headers: this.mRequest.headers
      });
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Instantiated data fetcher`);

      this.mFetcher.on('newDataReadable', () => this.onNewDataReadable());
      this.mFetcher.on('aborted', (_, error) => this.onError(error));

      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Calling fetcher.prepare()`);
      const responseHeaders = await this.mFetcher.prepare();
      if ( this.mAborted ) {
        MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Aborted after fetcher prepare. Reason: ${this.mError?.message}`);
        throw this.mError!;
      }

      this.mChunked = responseHeaders.statusCode === 200 && (responseHeaders as IMCHttpOkResponseHeaders).chunked === true;
      const rawHeaders = this.generateResponseHeaders(responseHeaders);

      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparation complete. Chunked: ${this.mChunked}, Raw Headers: ${rawHeaders}`);

      // 空文件
      if ( this.mFetcher.isDataEnd ) {
        MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] No data to stream (EOS reached during prepare). Marking response as done`);
        this.mDataEnd = true;
      }
      return rawHeaders;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Error during preparation: ${error.message}. Stack: ${error.stack}`);
      this.onError(error);
      throw error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    if (capacity <= 0) {
      MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] [read] Invalid read capacity: ${capacity}`);
      return undefined;
    }

    const fetcher = this.mFetcher;
    if ( fetcher == undefined ) return undefined;
    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] [read] Starting read data. Offset: ${fetcher.offset}, Readable: ${fetcher.readableLength}`);

    const data = await fetcher.read(capacity);
    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] [read] Read ${data?.byteLength ?? 0} bytes`);

    if ( data ) {
      if ( fetcher.isDataEnd ) {
        this.mDataEnd = true;
        MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] [read] End of stream detected (EOS)`);
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
        const totalSize = chunkHeader.byteLength + uint8Array.byteLength + chunkFooter.byteLength;

        // 拼接 buffer: 头部 + 数据 + 尾部
        const chunkedData = new ArrayBuffer(totalSize);
        const dataView = new Uint8Array(chunkedData);
        dataView.set(chunkHeader, 0);
        dataView.set(uint8Array, chunkHeader.byteLength);
        dataView.set(chunkFooter, chunkHeader.byteLength + uint8Array.byteLength);
        MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] [read] Returning chunked data. Chunk Size: ${chunkSizeHex}, Total: ${totalSize} bytes`);
        return chunkedData;
      }

      return data;
    }

    // no data read

    // Chunked终止块处理(只返回一次)
    if ( this.mDataEnd && this.mChunked && !this.mChunkReadEnd ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] [read] EOS reached. Returning final terminating chunk`);

      this.mChunkReadEnd = true;
      return buffer.from('0\r\n\r\n', 'utf-8').buffer;
    }
    else {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] [read] No data available to read`);
    }

    return data;
  }

  abort(error?: Error | undefined): void {
    if ( this.isCompleted ) {
      return;
    }

    this.mAborted = true;
    this.mError = error ?? new Error('Response was aborted');

    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Aborting response. Reason: ${this.mError!.message}, Stack: ${this.mError!.stack}`);

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
    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] ${event} callback registered`);

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
    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] ${event} callback removed`);

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