import { IMCHttpRequestRange, parseRequestRangeIfDefined } from "../defines/IMCHttpRequestRange";
import { parseResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { IMCMedia } from "../defines/IMCMedia";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
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
  private abortController?: MCAbortController;
  private downloadRangeStart?: number = undefined;

  // 传入之前请先对 media 做一次 readwriteRetain, loader 内部会在操作结束后执行对应的 readwriteRelease;
  constructor(media: IMCMedia, request: IMCMediaHttpContentRequest) {
    super();
    this.media = media;
    this.request = request;
  }

  protected async onPrepare(): Promise<void> {
    const requestRange = this.request.range ? this.request.range : parseRequestRangeIfDefined(this.request.headers['range']);
    const downloadRangeHeader = requestRange?.toRangeHeader(); // 'bytes=xxx-xxx'
    const downloadRequest = new MCDownload.DownloadRequest(this.request.url, this.request.headers);
    downloadRequest.setHeader('range', downloadRangeHeader);

    this.downloadRangeStart = requestRange?.rangeStart;
    this.abortController = new MCAbortController();
    try {
      await MCDownload.download(downloadRequest, {
        headersReceive: (headers) => this.onHeadersReceive(headers),
        dataReceive: (data) => this.onDataReceive(data),
        signal: this.abortController.signal,
      });
    } catch (e) {
      this.abort(e);
    }
  }

  protected onClearBefore(): void {
    this.abortController?.abort();
    this.abortController = undefined;
  }

  private async onHeadersReceive(headers: MCDownloadResponseHeaders): Promise<void> {
    return this.mLock.lockAsync(async () => {
      if ( this.mAborted || this.mDone ) {
        return;
      }

      if ( this.downloadRangeStart ) {
        const contentRangeHeader = headers['content-range'];
        if ( contentRangeHeader === undefined ) {
          throw new Error(`Response headers missing 'content-range' for url ${this.request.url}.`);
        }

        const contentRange = parseResponseContentRange(contentRangeHeader);
        // 确保服务器返回的 rangeStart 与请求时一致；
        if ( contentRange.rangeStart !== this.downloadRangeStart ) {
          throw new Error('Invalid server response: mismatched rangeStart.');
        }
      }

      const content = await this.media.createContentBy(headers); // content readwrite retained;
      // 获取数据长度
      const contentLengthHeader = headers['content-length'];
      // 服务器响应中必须指定 content-length;
      if ( contentLengthHeader === undefined ) {
        throw new Error(`Response headers missing 'content-length' for url ${this.request.url}.`);
      }
      const contentLength = parseInt(contentLengthHeader, 10);
      if (isNaN(contentLength)) {
        throw new Error(`Invalid 'content-length' value: ${contentLengthHeader} for url ${this.request.url}.`);
      }
      const range = new MCRange(content.contentOffset, contentLength);
      this.contentReady(content, range);
    }).catch((e: Error) => {
      this.abort(e);
      throw e;
    });
  }

  private async onDataReceive(data: ArrayBuffer): Promise<void> {
    return this.mLock.lockAsync(async () => {
      if ( this.mAborted || this.mDone ) {
        return;
      }
      await this.mContent?.writeData(data, data.byteLength);
    }).catch((e: Error) => {
      this.abort(e);
      throw e;
    });
  }
}