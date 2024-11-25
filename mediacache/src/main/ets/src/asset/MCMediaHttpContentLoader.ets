import { IMCHttpRequestRange, toRequestRangeHeader } from "../defines/IMCHttpRequestRange";
import { IMCMedia } from "../defines/IMCMedia";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export interface IMCMediaHttpContentRequest {
  readonly url: string;
  readonly range?: IMCHttpRequestRange;
  readonly headers: Record<string, string>;
}

export class MCMediaHttpContentLoader extends MCMediaContentLoader {
  private request: IMCMediaHttpContentRequest;
  private abortController?: MCAbortController;

  constructor(media: IMCMedia, request: IMCMediaHttpContentRequest) {
    super(media);
    this.request = request;
  }

  protected async onPrepare(): Promise<void> {
    const requestRange = this.request.range;
    const downloadRangeHeader = requestRange ? toRequestRangeHeader(requestRange?.rangeStart, requestRange?.rangeEnd, requestRange?.suffixLength) : undefined; // 'bytes=xxx-xxx'
    const downloadRequest = new MCDownload.DownloadRequest(this.request.url, this.request.headers);
    downloadRequest.setHeader('range', downloadRangeHeader);

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

      const content = await this.mMedia.createContentBy(headers);
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