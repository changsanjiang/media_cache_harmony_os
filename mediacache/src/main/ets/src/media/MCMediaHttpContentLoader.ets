import { IMCMediaContent, IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";
import { BusinessError } from "@kit.BasicServicesKit";
import { MCMedia } from "./MCMedia";

export class MCMediaHttpContentLoader extends MCMediaContentLoader {
  private media: MCMedia;
  private request: MCDownloadRequest;
  private abortController?: MCAbortController = undefined;
  private content?: IMCMediaContent = undefined;
  private writer?: IMCMediaContentWriter = undefined;

  constructor(media: MCMedia, request: MCDownloadRequest) {
    super();
    this.media = media;
    this.request = request;
  }

  protected async onPrepare(): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Preparing MCMediaHttpContentLoader for URL: ${this.request.url}.`);
    const downloadRequest = new MCDownload.Request(this.request.url, this.request.headers);
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Download request created for URL: ${this.request.url} with range: ${this.request.rangeHeader}.`);

    this.abortController = new MCAbortController();
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `AbortController initialized for request to ${this.request.url}.`);

    MCDownload.download(downloadRequest, {
      headersReceive: (headers) => this.onHeadersReceive(headers),
      dataReceive: (data) => this.onDataReceive(data),
      dataEnd: () => this.onDataEnd(),
      signal: this.abortController.signal,
    }).then((res) => {
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Download completed for URL: ${this.request.url}, Response headers: ${JSON.stringify(res.headers)}`);
      this.complete(res);
    }).catch((error: Error) => {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error during download for URL: ${this.request.url} - ${(error as Error).message ?? ((error as BusinessError).code)}`);
      if ( !this.mAborted ) {
        this.abort(error);
      }
      else {
        this.clearContent();
      }
    });
  }

  private async onHeadersReceive(headers: MCDownloadResponseHeaders): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Headers received for URL: ${this.request.url}: ${JSON.stringify(headers)}`);

    if ( this.mAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Loader for ${this.request.url} is aborted, ignoring headers.`);
      return;
    }

    try {
      // MCDownloadRequest 请求由 media 创建; 当其中包含范围字段时, 说明服务器必定支持范围请求;
      //
      //
      // 解析内容范围
      // 如果是 206 请求, response 必须指定 content-range 字段;
      // 如果是 200 请求: 依赖于 content-length 字段, 有些服务器可能不返回这个字段;
      //
      // 200 或 206 => {start, length};
      // 当 200 请求的响应未指定 content-length 字段时返回 {0, Number.MAX_SAFE_INTEGER}
      const contentRange = this.media.parseContentRange(this.request, headers);
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Content range parsed for URL: ${this.request.url}. Range: ${JSON.stringify(contentRange)}, Headers: ${JSON.stringify(headers)}}`);

      this.content = await this.media.createContentInRange(contentRange); // content readwrite retained;
      if ( this.mAborted ) {
        throw new Error(`xxx`);
      }

      this.writer = this.content.createWriter();
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Content created for URL: ${this.request.url} with range: ${JSON.stringify(contentRange)}, isTemp: ${this.content?.isTemp}.`);

      if ( !this.content.isTemp ) { // 临时内容需要在下载完成后才能通知父类 contentReady;
        this.onContentReady(this.content, contentRange);
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error in onHeadersReceive for URL: ${this.request.url} - ${(error as Error).message}`);
      if ( !this.mAborted ) {
        this.abort(error);
      }
      else {
        this.clearContent();
      }
      throw error as Error;
    }
  }

  private async onDataReceive(data: ArrayBuffer): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Data received for URL: ${this.request.url}: ${data.byteLength} bytes.`);

    if ( this.mAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Loader for ${this.request.url} is aborted, ignoring data.`);
      return;
    }

    try {
      await this.writer!.writeData(data, data.byteLength);
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Written ${data.byteLength} bytes to content for URL: ${this.request.url}.`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error in onDataReceive for URL: ${this.request.url} - ${(error as Error).message}`);
      if ( !this.mAborted ) {
        this.abort(error);
      }
      else {
        this.clearContent();
      }
      throw error as Error;
    }
  }

  private onDataEnd(): void {
    this.abortController = undefined;
  }

  private async complete(res: MCDownload.Response): Promise<void> { // 下载完成后调用
    if ( this.mAborted || !this.content || !this.content.isTemp ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Download for URL: ${this.request.url} is aborted or content is not temporary, skipping completion.`);
      return;
    }

    if ( res.statusCode !== 200 ) {
      this.abort(new Error(`Expected 200 status code, but got ${res.statusCode}`));
      return;
    }

    try {
      await this.media.copyTempContent(this.content); // 临时内容下载完成, 复制到正式目录;
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Temporary content copied for URL: ${this.request.url}.`);

      if ( this.mAborted ) {
        throw new Error(`xxx`);
      }

      const range = new MCRange(this.content.contentOffset, this.content.length);
      this.onContentReady(this.content, range); // 临时内容下载完成, 通知父类 contentReady;
    }
    catch (error) {
      if ( !this.mAborted ) {
        this.abort(error);
      }
      else {
        this.clearContent();
      }
      throw error as Error;
    }
  }

  protected onClearBefore(): void {
    if (this.abortController) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Aborting download.');
      this.abortController.abort();
      this.abortController = undefined;
    }
  }

  protected onClearAfter(): void {
    this.clearContent();
  }

  private clearContent() {
    if ( this.content ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Closing content writer.');
      this.writer?.close();
      this.writer = undefined;
      if ( this.content.isTemp ) this.media.destroyTempContent(this.content);
      this.content = undefined;
    }
  }
}