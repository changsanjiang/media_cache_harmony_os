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

/** 下载全部数据, 通过 media.applyProxy 生成代理内容后写入到content中; */
export class MCMediaProxyContentLoader extends MCMediaContentLoader {
  private mMedia: MCMedia;
  private mRequest: MCDownloadRequest;
  private mAbortController?: MCAbortController = undefined;
  private mContent?: IMCMediaContent = undefined;
  private mWriter?: IMCMediaContentWriter = undefined;

  constructor(media: MCMedia, request: MCDownloadRequest) {
    super();
    this.mMedia = media;
    this.mRequest = request;
  }

  async prepare(): Promise<void> {
    if ( this.mRequest.rangeHeader ) {
      this.abort(new Error(`[Proxy] Range requests are not supported. URL: ${this.mRequest.url}`)); // 目前仅处理200请求, request 的 Headers 中不能包含 Range;
      return;
    }

    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Proxy] Preparing loader for URL: ${this.mRequest.url}.`);

    const downloadRequest = new MCDownload.Request(this.mRequest.url, this.mRequest.headers);
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Download request created for URL: ${this.mRequest.url}.`);

    this.mAbortController = new MCAbortController();
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Starting download for URL: ${this.mRequest.url}.`);
    MCDownload.download(downloadRequest, {
      signal: this.mAbortController.signal,
    }).then((res) => {
      this.mAbortController = undefined;
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Download completed for URL: ${this.mRequest.url}, Response: ${JSON.stringify(res.headers)}`);
      this.onComplete(res);
    }).catch((error: Error) => {
      this.mAbortController = undefined;
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Proxy] Error during download for URL: ${this.mRequest.url} - ${(error as Error).message ?? ((error as BusinessError).code)}`);
      if ( this.mAbortController ) this.mAbortController = undefined;
      this.onError(error);
    });
  }

  private async onComplete(res: MCDownload.Response): Promise<void> { // 下载完成后调用
    if ( this.isAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Download for URL: ${this.mRequest.url} is aborted, skipping completion.`);
      return;
    }

    try {
      if ( res.statusCode !== 200 ) {
        throw new Error(`Expected 200 status code, but got ${res.statusCode}.`)
      }

      this.mContent = await this.mMedia.createContentAt(0, true);
      if ( this.isAborted ) {
        throw new Error(`Loader aborted after content creation.`);
      }

      // apply proxy;
      const data = res.body ? await this.mMedia.applyProxy(res.requestUrl, res.currentUrl, res.body) : undefined;
      if ( this.isAborted ) {
        throw new Error(`Loader aborted after proxy content data.`);
      }

      // write buffer to content;
      this.mWriter = this.mContent.createWriter();
      if ( data ) await this.mWriter.writeData(data, data.byteLength);
      if ( this.isAborted ) {
        throw new Error(`Loader aborted after writing data.`);
      }

      // copy temp content;
      await this.mMedia.copyTempContent(this.mContent); // 临时内容下载完成, 复制到正式目录;
      if ( this.isAborted ) {
        throw new Error(`Loader aborted after copying temporary content.`);
      }
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Temporary content copied for URL: ${this.mRequest.url}.`);

      // content ready to read
      const range = new MCRange(this.mContent.contentOffset, this.mContent.length);
      this.onPrepared(this.mContent, range); // 临时内容下载完成, 通知父类 contentReady;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Proxy] Error during onComplete for URL: ${this.mRequest.url} - ${error.message}`);
      this.onError(error)
      throw error as Error;
    }
  }

  protected async onClear(): Promise<void> { // 父类在清理资源时调用;
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Starting onClear. AbortController: ${this.mAbortController}, Content: ${this.mContent}, ContentWriter: ${this.mWriter}.`);

    if (this.mAbortController) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Proxy] Aborting download.');
      this.mAbortController.abort();
      this.mAbortController = undefined;
    }

    if ( this.mContent ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Proxy] Closing content writer.');
      try { await this.mWriter?.close(); } catch (_) { }
      this.mWriter = undefined;
      if ( this.mContent.isTemp ) try { await this.mMedia.destroyTempContent(this.mContent); } catch (_) { }
      this.mContent = undefined;
    }
  }
}