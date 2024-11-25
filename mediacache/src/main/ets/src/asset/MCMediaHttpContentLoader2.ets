import { parseRequestRangeIfDefined, toRequestRangeHeader } from "../defines/IMCHttpRequestRange";
import { parseResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";
import { IMCMediaHttpContentRequest } from "./MCMediaHttpContentLoader";

/** 断点下载; */
export class MCMediaHttpContentLoader2 extends MCMediaContentLoader {
  private media: IMCMedia;
  private request: IMCMediaHttpContentRequest;
  private content: IMCMediaContent;
  private abortController?: MCAbortController;
  private downloadRangeStart = 0;

  // 传入之前请先对 content 做一次 readwriteRetain, loader 内部会在操作结束后执行对应的 readwriteRelease;
  constructor(media: IMCMedia, request: IMCMediaHttpContentRequest, content: IMCMediaContent) {
    super();
    this.media = media;
    this.request = request;
    this.content = content;
  }

  protected async onPrepare(): Promise<void> {
    const requestRange = this.request.range ? this.request.range : parseRequestRangeIfDefined(this.request.headers['range']);
    // 必须指定请求范围和 rangeStart;
    if (!requestRange || !requestRange.rangeStart) {
      throw new Error('Invalid request range: rangeStart must be specified for breakpoint downloads.');
    }

    const requestRangeStart = requestRange.rangeStart;
    const requestRangeEnd = requestRange.rangeEnd;
    const requestSuffixLength = requestRange.suffixLength;

    let downloadRangeStart = requestRangeStart;
    let downloadRangeEnd = requestRangeEnd;
    let downloadSuffixLength = requestSuffixLength;

    // 检测 rangeStart 的合法性;
    if ( requestRangeStart > this.content.contentOffset ) {
      throw new Error('Invalid range: rangeStart exceeds the current content offset.');
    }

    // 调整请求范围
    const offset = this.content.contentOffset;
    const len = this.content.unsafeLength;
    downloadRangeStart = offset + len; // 更新需要下载的数据的起始偏移量;

    // 检测 rangeEnd 的合法性;
    if ( requestRangeEnd ) {
      const totalLength = await this.media.totalLength;
      if ( requestRangeEnd >= totalLength ) {
        throw new Error('Invalid range: rangeEnd exceeds total media length.');
      }

      const loadRange = new MCRange(requestRangeStart!, requestRangeEnd);
      this.contentReady(this.content, loadRange);

      // 确定是否存在未下载的部分, 不需要下载就直接返回;
      if ( requestRangeEnd <= downloadRangeStart ) {
        return;
      }
    }

    // 进行下载: 设置 Range 头并发送 HTTP 请求;
    const downloadRangeHeader = toRequestRangeHeader(downloadRangeStart, downloadRangeEnd, downloadSuffixLength); // 'bytes=xxx-xxx'
    const downloadRequest = new MCDownload.DownloadRequest(this.request.url, this.request.headers);
    downloadRequest.setHeader('range', downloadRangeHeader);

    this.downloadRangeStart = downloadRangeStart;
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
    this.content?.readwriteRelease();
  }

  private async onHeadersReceive(headers: MCDownloadResponseHeaders): Promise<void> {
    return this.mLock.lockAsync(async () => {
      if ( this.mAborted || this.mDone ) {
        return;
      }

      const contentRangeHeader = headers['content-range'];
      if ( contentRangeHeader === undefined ) {
        throw new Error(`Response headers missing 'content-range' for url ${this.request.url}.`);
      }

      const contentRange = parseResponseContentRange(contentRangeHeader);

      // 确保服务器返回的 rangeStart 与请求时一致；
      if ( contentRange.rangeStart !== this.downloadRangeStart ) {
        throw new Error('Invalid server response: mismatched rangeStart.');
      }

      // 检查 Content-Length 是否存在；
      const contentLengthHeader = headers['content-length'];
      if ( contentLengthHeader === undefined ) {
        throw new Error(`Response headers missing 'content-length' for url ${this.request.url}.`);
      }

      const contentLength = parseInt(contentLengthHeader, 10);
      const loadRange = new MCRange(contentRange.rangeStart, contentLength);

      this.content.readwriteRetain();
      this.contentReady(this.content, loadRange);
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
      await this.content?.writeData(data, data.byteLength);
    }).catch((e: Error) => {
      this.abort(e);
      throw e;
    });
  }
}