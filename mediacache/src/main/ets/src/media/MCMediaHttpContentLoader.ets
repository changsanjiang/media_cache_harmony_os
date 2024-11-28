import { IMCHttpRequestRange, parseRequestRangeIfDefined } from "../defines/IMCHttpRequestRange";
import { parseResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export interface IMCMediaHttpContentRequest {
  readonly url: string;

  // 优先通过 range 属性获取请求范围;
  // 如果 range 未设置, 将会尝试从 headers 中获取请求范围;
  readonly range?: IMCHttpRequestRange;
  readonly headers: Record<string, string>;
}

export class MCMediaHttpContentLoader extends MCMediaContentLoader {
  private media: IMCMedia;
  private request: IMCMediaHttpContentRequest;
  private abortController?: MCAbortController = undefined;
  private downloadRangeStart?: number = undefined;
  private content?: IMCMediaContent = undefined;

  constructor(media: IMCMedia, request: IMCMediaHttpContentRequest) {
    super();
    this.media = media;
    this.request = request;
  }

  protected async onPrepare(): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Preparing MCMediaHttpContentLoader for URL: ${this.request.url}.`);

    const requestRange = this.request.range ? this.request.range : parseRequestRangeIfDefined(this.request.headers['range']);
    const downloadRangeHeader = requestRange?.toRangeHeader(); // 'bytes=xxx-xxx'
    const downloadRequest = new MCDownload.DownloadRequest(this.request.url, this.request.headers);
    downloadRequest.setHeader('range', downloadRangeHeader);

    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Download request created for URL: ${this.request.url} with range: ${downloadRangeHeader}.`);

    this.downloadRangeStart = requestRange?.rangeStart;
    this.abortController = new MCAbortController();
    MCDownload.download(downloadRequest, {
      headersReceive: (headers) => this.onHeadersReceive(headers),
      dataReceive: (data) => this.onDataReceive(data),
      signal: this.abortController.signal,
    }).catch((error: Error) => this.abort(error));
  }

  protected onClearBefore(): void {
    if (this.abortController) {
      MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Aborting download.');
      this.abortController.abort();
      this.abortController = undefined;
    }
  }

  private async onHeadersReceive(headers: MCDownloadResponseHeaders): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Headers received for URL: ${this.request.url}.`);

    return this.mLock.lockAsync(async () => {
      try {
        if ( this.mAborted || this.mDone ) {
          MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Loader is aborted or done, ignoring headers.');
          return;
        }

        if ( this.downloadRangeStart ) {
          const contentRangeHeader = headers['content-range'];
          if ( contentRangeHeader === undefined ) {
            throw new Error(`Response headers missing 'content-range' for URL ${this.request.url}.`);
          }

          const contentRange = parseResponseContentRange(contentRangeHeader);
          // 确保服务器返回的 rangeStart 与请求时一致；
          if ( contentRange.rangeStart !== this.downloadRangeStart ) {
            throw new Error('Invalid server response: mismatched rangeStart.');
          }
        }

        this.content = await this.media.createContentBy(headers); // content readwrite retained;
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Content created for URL: ${this.request.url} Headers: ${JSON.stringify(headers)}.`);

        // 获取数据长度
        const contentLengthHeader = headers['content-length'];
        // 服务器响应中必须指定 content-length;
        if ( contentLengthHeader === undefined ) {
          throw new Error(`Response headers missing 'content-length' for URL: ${this.request.url}.`);
        }
        const contentLength = parseInt(contentLengthHeader, 10);
        if (isNaN(contentLength)) {
          throw new Error(`Invalid 'content-length' value: ${contentLengthHeader} for URL: ${this.request.url}.`);
        }
        const range = new MCRange(this.content.contentOffset, contentLength);
        this.contentReady(this.content, range);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error in onHeadersReceive: ${(error as Error).message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  private onDataReceive(data: ArrayBuffer): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Data received: ${data.byteLength} bytes.`);

    return this.mLock.lockAsync(async () => {
      if ( this.mAborted || this.mDone ) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Loader is aborted or done, ignoring received data.');
        return;
      }

      try {
        await this.content!.writeData(data, data.byteLength);
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Data written to content: ${data.byteLength} bytes.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error in onDataReceive: ${(error as Error).message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  protected onClearAfter(): void {
    if ( this.content ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Closing content writer.');
      this.content.closeWrite();
      this.content = undefined;
    }
  }
}