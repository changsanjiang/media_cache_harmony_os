import { MCMediaContentLoader } from "./MCMediaContentLoader";
import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { BusinessError } from "@kit.BasicServicesKit";
import { MCUtils } from "../../../../../Index";

/** 下载全部数据, 通过proxyHandler生成代理内容后写入到content中; */
export class MCMediaProxyContentLoader extends MCMediaContentLoader {
  private media: IMCMedia;
  private request: MCDownloadRequest;
  private abortController?: MCAbortController = undefined;
  private content?: IMCMediaContent = undefined;

  private mBuffer?: ArrayBuffer = undefined;
  private mProxyContentHandler: (contentData: ArrayBuffer) => ArrayBuffer | Promise<ArrayBuffer>;

  constructor(media: IMCMedia, request: MCDownloadRequest, proxyContentHandler: (contentData: ArrayBuffer) => ArrayBuffer | Promise<ArrayBuffer>) {
    if ( request.rangeHeader ) {
      throw new Error(`xxx`); // 目前仅处理200请求, request 的 Header 中不能包含 Range;
    }

    super();
    this.media = media;
    this.request = request;
    this.mProxyContentHandler = proxyContentHandler;
  }

  protected async onPrepare(): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Preparing MCMediaProxyContentLoader for URL: ${this.request.url}.`);
    const downloadRequest = new MCDownload.Request(this.request.url, this.request.headers);
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Download request created for URL: ${this.request.url}.`);

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

    if ( this.mAborted || this.mDone ) {
      MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Loader for ${this.request.url} is aborted or done, ignoring headers.`);
      return;
    }
  }

  private async onDataReceive(data: ArrayBuffer): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Data received for URL: ${this.request.url}: ${data.byteLength} bytes.`);

    if ( this.mAborted || this.mDone ) {
      MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Loader for ${this.request.url} is aborted or done, ignoring data.`);
      return;
    }

    if ( !this.mBuffer ) {
      this.mBuffer = data;
    }
    else {
      this.mBuffer = MCUtils.mergeArrayBuffers(this.mBuffer, data);
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

    this.content = await this.media.createContentAt(0, true);
    const data = this.mBuffer ? await this.mProxyContentHandler(this.mBuffer) : undefined;
    if ( data ) await this.content.writeData(data, data.byteLength);
    await this.media.copyTempContent(this.content); // 临时内容下载完成, 复制到正式目录;
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Temporary content copied for URL: ${this.request.url}.`);

    const range = new MCRange(this.content.contentOffset, this.content.length);
    this.onContentReady(this.content, range); // 临时内容下载完成, 通知父类 contentReady;
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
  }
}