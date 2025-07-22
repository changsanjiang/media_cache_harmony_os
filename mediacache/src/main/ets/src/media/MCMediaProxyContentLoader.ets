import { IMCMediaContent, IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { BusinessError } from "@kit.BasicServicesKit";
import { MCMedia } from "./MCMedia";
import { MCMediaContentLoader } from "./MCMediaContentLoader";
import MCConfigs from "../utils/MCConfigs";

/** 下载全部数据, 通过 media.applyProxy 生成代理内容后写入到content中; */
export class MCMediaProxyContentLoader extends MCMediaContentLoader {
  private mMedia: MCMedia;
  private mRequest: MCDownloadRequest;
  private mDownloadAbortController?: MCAbortController = undefined;
  private mContent?: IMCMediaContent = undefined;
  private mWriter?: IMCMediaContentWriter = undefined;

  constructor(media: MCMedia, request: MCDownloadRequest) {
    super();
    this.mMedia = media;
    this.mRequest = request;
  }

  async prepare(): Promise<void> {
    if ( this.mRequest.rangeHeader ) {
      this.onError(new Error(`[Proxy] Range requests are not supported. URL: ${this.mRequest.url}`)); // 目前仅处理200请求, request 的 Headers 中不能包含 Range;
      return;
    }

    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Proxy] Preparing loader for URL: ${this.mRequest.url}.`);

    const downloadRequest = new MCDownloadRequest(this.mRequest.url, this.mRequest.headers);
    if ( MCConfigs.requestHandler ) {
      MCConfigs.requestHandler(downloadRequest);
    }
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Download request created for URL: ${this.mRequest.url}.`);

    this.mDownloadAbortController = new MCAbortController();
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Starting download for URL: ${this.mRequest.url}.`);
    MCDownload.download(downloadRequest, {
      signal: this.mDownloadAbortController.signal,
    }).then((res) => {
      this.mDownloadAbortController = undefined;
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Download completed for URL: ${this.mRequest.url}, Response: ${JSON.stringify(res.headers)}`);
      this.onComplete(res);
    }).catch((error: Error) => {
      this.mDownloadAbortController = undefined;
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Proxy] Error during download for URL: ${this.mRequest.url} - ${(error as Error).message ?? ((error as BusinessError).code)}`);
      if ( this.mDownloadAbortController ) this.mDownloadAbortController = undefined;
      this.onError(error);
    });
  }

  private async onComplete(res: MCDownload.Response): Promise<void> { // 下载完成后调用
    if ( this.isAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Download aborted for URL: ${this.mRequest.url}. Completion process skipped.`);
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
      await this.mMedia.finalize(this.mContent); // 临时内容下载完成, 交付转为正式内容;
      if ( this.isAborted ) {
        throw new Error(`Loader aborted after copying temporary content.`);
      }
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Temporary content finalized and stored for URL: ${this.mRequest.url}.`);

      // content ready to read
      const range = new MCRange(this.mContent.contentOffset, this.mContent.length);
      this.onPrepared(this.mContent, range); // 临时内容下载完成, 通知父类 contentReady;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Proxy] Error during onComplete for URL: ${this.mRequest.url} - ${error.message}. Stack trace: ${error.stack}`);
      this.onError(error)
      throw error as Error;
    }
  }

  protected async onClear(): Promise<void> { // 父类在清理资源时调用;
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Proxy] Starting onClear for request: ${this.mRequest.url}. AbortController: ${this.mDownloadAbortController}, Content: ${this.mContent}, ContentWriter: ${this.mWriter}.`);

    if ( this.mDownloadAbortController ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Proxy] Aborting download.');
      this.mDownloadAbortController.abort();
      this.mDownloadAbortController = undefined;
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Proxy] Download aborted.');
    }

    const content = this.mContent;
    const writer = this.mWriter;

    if ( content ) {
      this.mContent = undefined;
      this.mWriter = undefined;

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Proxy] Closing content writer.');
      try {
        await writer?.close();
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Proxy] Content writer closed successfully.');
      }
      catch (error) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `[Proxy] Error closing writer for request: ${this.mRequest.url} - ${(error as Error).message}. Stack trace: ${error.stack}`);
      }

      if ( content.isTemp ) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Proxy] Destroying temporary content.');
        try {
          await this.mMedia.destroy(content);
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Proxy] Temporary content destroyed successfully.');
        }
        catch (error) {
          MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `[Proxy] Error destroying temporary content for request: ${this.mRequest.url} - ${(error as Error).message}. Stack trace: ${error.stack}`);
        }
      }
    }
  }
}