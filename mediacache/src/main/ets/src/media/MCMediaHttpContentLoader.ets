import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { MCMediaContentLoader } from "./MCMediaContentLoader";
import { BusinessError } from "@kit.BasicServicesKit";

export class MCMediaHttpContentLoader extends MCMediaContentLoader {
  private media: IMCMedia;
  private request: MCDownloadRequest;
  private abortController?: MCAbortController = undefined;
  private content?: IMCMediaContent = undefined;

  constructor(media: IMCMedia, request: MCDownloadRequest) {
    super();
    this.media = media;
    this.request = request;
    media.readwriteRetain();
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
      this.abort(error);
    });
  }

  private async onHeadersReceive(headers: MCDownloadResponseHeaders): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Headers received for URL: ${this.request.url}: ${JSON.stringify(headers)}`);

    try {
      if ( this.mAborted || this.mDone ) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Loader for ${this.request.url} is aborted or done, ignoring headers.`);
        return;
      }
      // MCDownloadRequest 请求由 media 创建; 当其中包含范围字段时, 说明服务器必定支持范围请求;
      //
      //
      // 解析内容范围
      // 如果是 206 请求, response 必须指定 content-range 字段;
      // 如果是 200 请求: 依赖于 content-length 字段, 有些服务器可能不返回这个字段;
      //
      // 200 或 206 => {start, length};
      // 当 200 请求的响应未指定 content-length 字段时返回 {0, Number.MAX_SAFE_INTEGER}
      const contentRange = await this.media.parseContentRange(this.request, headers);
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Content range parsed for URL: ${this.request.url}. Range: ${JSON.stringify(contentRange)}, Headers: ${JSON.stringify(headers)}}`);

      this.content = await this.media.createContentInRange(contentRange); // content readwrite retained;
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Content created for URL: ${this.request.url} with range: ${JSON.stringify(contentRange)}, isTemp: ${this.content?.isTemp}.`);

      if ( !this.content.isTemp ) { // 临时内容需要在下载完成后才能通知父类 contentReady;
        this.contentReady(this.content, contentRange);
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error in onHeadersReceive for URL: ${this.request.url} - ${(error as Error).message}`);
      this.abort(error);
      throw error as Error;
    }
  }

  private async onDataReceive(data: ArrayBuffer): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Data received for URL: ${this.request.url}: ${data.byteLength} bytes.`);

    if ( this.mAborted || this.mDone ) {
      MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Loader for ${this.request.url} is aborted or done, ignoring data.`);
      return;
    }

    try {
      await this.content!.writeData(data, data.byteLength);
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Written ${data.byteLength} bytes to content for URL: ${this.request.url}.`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error in onDataReceive for URL: ${this.request.url} - ${(error as Error).message}`);
      this.abort(error);
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

    await this.media.copyTempContent(this.content); // 临时内容下载完成, 复制到正式目录;
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Temporary content copied for URL: ${this.request.url}.`);

    const range = new MCRange(this.content.contentOffset, this.content.length);
    this.contentReady(this.content, range); // 临时内容下载完成, 通知父类 contentReady;
  }

  protected onClearBefore(): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing custom operations before clearing.`);

    if (this.abortController) {
      MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Aborting download.');
      this.abortController.abort();
      this.abortController = undefined;
    }
  }

  protected onClearAfter(): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing custom operations after clearing.`);

    if ( this.content ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Closing content writer.');
      !this.content.isTemp ? this.content.closeWrite() : this.media.destroyTempContent(this.content);
      this.content = undefined;
    }
    this.media.readwriteRelease();
  }
}