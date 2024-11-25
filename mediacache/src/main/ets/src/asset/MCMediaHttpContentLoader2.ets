import { toRequestRangeHeader } from "../common/IMCHttpRequestRange";
import { parseResponseContentRange } from "../common/IMCHttpResponseContentRange";
import { IMCMedia } from "../common/IMCMedia";
import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";
import { IMCMediaHttpContentRequest } from "./MCMediaHttpContentLoader";

/** 断点下载; */
export class MCMediaHttpContentLoader2 extends MCMediaContentLoader {
  private request: IMCMediaHttpContentRequest;
  private content: IMCMediaContent;
  private abortController?: MCAbortController;

  // 传入之前请先对 content 做一次 readwriteRetain, loader 内部会在操作结束后执行对应的 readwriteRelease;
  constructor(media: IMCMedia, request: IMCMediaHttpContentRequest, content: IMCMediaContent) {
    super(media);
    this.request = request;
    this.content = content;
  }

  protected async onPrepare(): Promise<void> {
    const requestRange = this.request.range;
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
      throw new Error('xxx');
    }

    // 调整请求范围
    const offset = this.content.contentOffset;
    const len = this.content.unsafeLength;
    downloadRangeStart = offset + len; // 更新需要下载的数据的起始偏移量;

    // 检测 rangeEnd 的合法性;
    if ( requestRangeEnd ) {
      const totalLength = await this.mMedia.totalLength;
      if ( requestRangeEnd >= totalLength ) {
        throw new Error(`xxx`);
      }

      const loadRange = new MCRange(requestRangeStart!, requestRangeEnd);
      this.contentReady(this.content, loadRange);

      // 确定是否存在未下载的部分, 不需要下载就直接返回;
      if ( requestRangeEnd <= downloadRangeStart ) {
        return;
      }
    }

    // 进行下载
    const downloadRangeHeader = toRequestRangeHeader(downloadRangeStart, downloadRangeEnd, downloadSuffixLength); // 'bytes=xxx-xxx'
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
    this.content?.readwriteRelease();
  }

  private async onHeadersReceive(headers: MCDownloadResponseHeaders): Promise<void> {
    return this.mLock.lockAsync(async () => {
      if ( this.mAborted || this.mDone ) {
        return;
      }

      const contentRangeHeader = headers['content-range'];
      if ( contentRangeHeader === undefined ) {
        throw new Error('Server must support range requests.');
      }

      const contentRange = parseResponseContentRange(contentRangeHeader);
      // 获取数据长度
      const contentLengthHeader = headers['content-length'];
      // 服务器响应中必须指定 content-length;
      if ( contentLengthHeader === undefined ) {
        throw new Error('Server response must specify content-length.');
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