import { IMCMediaContent, IMCMediaContentWriter } from "../defines/IMCMediaContent";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAbortController } from "../utils/MCAbortController";
import MCDownload from "../utils/MCDownload";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { BusinessError } from "@kit.BasicServicesKit";
import { MCMedia } from "./MCMedia";
import { MCMediaContentLoader } from "./MCMediaContentLoader";

export class MCMediaHttpContentLoader extends MCMediaContentLoader {
  private mMedia: MCMedia;
  private mRequest: MCDownloadRequest;
  private mAbortController?: MCAbortController = undefined;
  private mContent?: IMCMediaContent = undefined;
  private mWriter?: IMCMediaContentWriter = undefined;
  private mHeadersReceivePromise?: Promise<void> = undefined;

  constructor(media: MCMedia, request: MCDownloadRequest) {
    super();
    this.mMedia = media;
    this.mRequest = request;
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Preparing loader for URL: ${this.mRequest.url}.`);

    const downloadRequest = new MCDownload.Request(this.mRequest.url, this.mRequest.headers);
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Download request created for URL: ${this.mRequest.url} with range: ${this.mRequest.rangeHeader}.`);

    this.mAbortController = new MCAbortController();
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Starting download for URL: ${this.mRequest.url}.`);
    MCDownload.download(downloadRequest, {
      headersReceive: (headers) => this.onHeadersReceive(headers),
      dataReceive: (data) => this.onDataReceive(data),
      dataEnd: () => this.onDataEnd(),
      signal: this.mAbortController.signal,
    }).then((res) => {
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Download completed for URL: ${this.mRequest.url}, Response headers: ${JSON.stringify(res.headers)}`);
      this.onComplete(res);
    }).catch((error: Error) => {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Http] Error during download for URL: ${this.mRequest.url} - ${(error as Error).message ?? ((error as BusinessError).code)}`);
      if ( this.mAbortController ) this.mAbortController = undefined;
      this.onError(error);
    });
  }

  private onHeadersReceive(headers: MCDownloadResponseHeaders): void { // 接收到headers的响应
    this.mHeadersReceivePromise = new Promise(async (resolve) => {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Headers received for URL: ${this.mRequest.url}: ${JSON.stringify(headers)}`);

      if ( this.isAborted ) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Loader aborted, ignoring headers for URL: ${this.mRequest.url}.`);
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
        const contentRange = this.mMedia.parseContentRange(this.mRequest, headers);
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Content range parsed for URL: ${this.mRequest.url}. Range: ${JSON.stringify(contentRange)}, Headers: ${JSON.stringify(headers)}}`);

        this.mContent = await this.mMedia.createContentInRange(contentRange);
        if ( this.isAborted ) {
          throw new Error(`Loader aborted after content creation.`);
        }

        this.mWriter = this.mContent.createWriter();
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Content created for URL: ${this.mRequest.url} with range: ${JSON.stringify(contentRange)}, isTemp: ${this.mContent?.isTemp}.`);

        // 如果不是临时内容则立即通知父类 onPrepared, 否则等待临时内容下载完成后再通知父类;
        if ( !this.mContent.isTemp ) {
          MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Content ready. Invoking onPrepared.`);
          this.onPrepared(this.mContent, contentRange);
        }
        else {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Temporary content detected, waiting for full download.`);
        }
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Http] Error processing headers for URL: ${this.mRequest.url} - ${(error as Error).message}`);
        this.onError(error);
        throw error as Error;
      }
      finally {
        resolve();
      }
    });
  }

  private async onDataReceive(data: ArrayBuffer): Promise<void> { // 接收到下载的数据
    await this.mHeadersReceivePromise!;

    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Data received for URL: ${this.mRequest.url}: ${data.byteLength} bytes.`);

    if ( this.isAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Loader for ${this.mRequest.url} is aborted, ignoring data.`);
      return;
    }

    try {
      await this.mWriter!.writeData(data, data.byteLength);
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Written ${data.byteLength} bytes to content for URL: ${this.mRequest.url}.`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Http] Error writing data for URL: ${this.mRequest.url} - ${(error as Error).message}`);
      this.onError(error);
      throw error as Error;
    }
  }

  private onDataEnd(): void {
    this.mAbortController = undefined;
  }

  private async onComplete(res: MCDownload.Response): Promise<void> { // 下载完成后调用
    if ( this.isAborted || !this.mContent || !this.mContent.isTemp ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Download for URL: ${this.mRequest.url} is aborted or content is not temporary, skipping completion.`);
      return;
    }

    try {
      if ( res.statusCode !== 200 ) {
        throw new Error(`Expected 200 status code, but got ${res.statusCode}`);
      }

      await this.mMedia.copyTempContent(this.mContent); // 临时内容下载完成, 复制到正式目录;
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Temporary content copied for URL: ${this.mRequest.url}.`);

      if ( this.isAborted ) {
        throw new Error(`Loader aborted after copying temporary content.`);
      }

      const range = new MCRange(this.mContent.contentOffset, this.mContent.length);
      this.onPrepared(this.mContent, range); // 临时内容下载完成, 通知父类 onPrepared;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Http] Error during onComplete for URL: ${this.mRequest.url} - ${error.message}`);
      this.onError(error);
      throw error as Error;
    }
  }

  protected async onClear(): Promise<void> { // 父类清理资源时调用
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Starting onClear. AbortController: ${this.mAbortController}, Content: ${this.mContent}, ContentWriter: ${this.mWriter}.`);

    if ( this.mAbortController ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Http] Aborting download.');
      this.mAbortController.abort();
      this.mAbortController = undefined;
    }

    if ( this.mContent ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Http] Closing content writer.');
      try { await this.mWriter?.close(); } catch (_) { }
      this.mWriter = undefined;
      if ( this.mContent.isTemp ) try { await this.mMedia.destroyTempContent(this.mContent); } catch (_) { }
      this.mContent = undefined;
    }
  }
}