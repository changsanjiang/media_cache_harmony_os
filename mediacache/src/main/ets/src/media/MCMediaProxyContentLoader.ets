import { IMCMediaContent, IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { BusinessError } from "@kit.BasicServicesKit";
import { MCUtils } from "../../../../../Index";
import { MCMedia } from "./MCMedia";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

/** 下载全部数据, 通过proxyHandler生成代理内容后写入到content中; */
export class MCMediaProxyContentLoader extends MCMediaContentLoader {
  private mMedia: MCMedia;
  private mRequest: MCDownloadRequest;
  private mAbortController?: MCAbortController = undefined;
  private mContent?: IMCMediaContent = undefined;
  private mWriter?: IMCMediaContentWriter = undefined;
  private mBuffer?: ArrayBuffer = undefined;

  constructor(media: MCMedia, request: MCDownloadRequest) {
    super();
    this.mMedia = media;
    this.mRequest = request;
  }

  async prepare(): Promise<void> {
    if ( this.mRequest.rangeHeader ) {
      this.abort(new Error(`xxx`)); // 目前仅处理200请求, request 的 Header 中不能包含 Range;)
      return;
    }

    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Preparing MCMediaProxyContentLoader for URL: ${this.mRequest.url}.`);
    const downloadRequest = new MCDownload.Request(this.mRequest.url, this.mRequest.headers);
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Download request created for URL: ${this.mRequest.url}.`);

    this.mAbortController = new MCAbortController();
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `AbortController initialized for request to ${this.mRequest.url}.`);

    MCDownload.download(downloadRequest, {
      headersReceive: (headers) => this.onHeadersReceive(headers),
      dataReceive: (data) => this.onDataReceive(data),
      dataEnd: () => this.onDataEnd(),
      signal: this.mAbortController.signal,
    }).then((res) => {
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Download completed for URL: ${this.mRequest.url}, Response headers: ${JSON.stringify(res.headers)}`);
      this.complete(res);
    }).catch((error: Error) => {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error during download for URL: ${this.mRequest.url} - ${(error as Error).message ?? ((error as BusinessError).code)}`);
      if ( this.mAbortController ) this.mAbortController = undefined;
      this.onError(error);
    });
  }

  private async onHeadersReceive(headers: MCDownloadResponseHeaders): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Headers received for URL: ${this.mRequest.url}: ${JSON.stringify(headers)}`);

    if ( this.isAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Loader for ${this.mRequest.url} is aborted or done, ignoring headers.`);
      return;
    }
  }

  private async onDataReceive(data: ArrayBuffer): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Data received for URL: ${this.mRequest.url}: ${data.byteLength} bytes.`);

    if ( this.isAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Loader for ${this.mRequest.url} is aborted or done, ignoring data.`);
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
    this.mAbortController = undefined;
  }

  private async complete(res: MCDownload.Response): Promise<void> { // 下载完成后调用
    if ( this.isAborted || !this.mContent || !this.mContent.isTemp ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Download for URL: ${this.mRequest.url} is aborted or content is not temporary, skipping completion.`);
      return;
    }

    try {
      if ( res.statusCode !== 200 ) {
        throw new Error(`Expected 200 status code, but got ${res.statusCode}`)
      }

      this.mContent = await this.mMedia.createContentAt(0, true);
      if ( this.isAborted ) {
        throw new Error(`The contet loader has been aborted.`);
      }

      // apply proxy;
      const data = this.mBuffer ? await this.mMedia.applyProxy(res.requestUrl, res.currentUrl, this.mBuffer) : undefined;
      if ( this.isAborted ) {
        throw new Error(`xxx`);
      }

      // write buffer to content;
      this.mWriter = this.mContent.createWriter();
      if ( data ) await this.mWriter.writeData(data, data.byteLength);
      if ( this.isAborted ) {
        throw new Error(`xxx`);
      }

      // copy temp content;
      await this.mMedia.copyTempContent(this.mContent); // 临时内容下载完成, 复制到正式目录;
      if ( this.isAborted ) {
        throw new Error(`xxx`);
      }
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Temporary content copied for URL: ${this.mRequest.url}.`);

      // content ready to read
      const range = new MCRange(this.mContent.contentOffset, this.mContent.length);
      this.onPrepared(this.mContent, range); // 临时内容下载完成, 通知父类 contentReady;
    }
    catch (error) {
      this.onError(error)
      throw error as Error;
    }
  }

  protected async onClear(): Promise<void> {
    if (this.mAbortController) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Aborting download.');
      this.mAbortController.abort();
      this.mAbortController = undefined;
    }

    if ( this.mContent ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Closing content writer.');
      try { await this.mWriter?.close(); } catch (_) { }
      this.mWriter = undefined;
      if ( this.mContent.isTemp ) try { await this.mMedia.destroyTempContent(this.mContent); } catch (_) { }
      this.mContent = undefined;
    }
  }
}