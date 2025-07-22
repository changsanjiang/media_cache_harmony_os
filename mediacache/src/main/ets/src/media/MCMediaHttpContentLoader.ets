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
import MCConfigs from "../utils/MCConfigs";

export class MCMediaHttpContentLoader extends MCMediaContentLoader {
  private mMedia: MCMedia;
  private mRequest: MCDownloadRequest;
  private mDownloadAbortController?: MCAbortController = undefined;
  private mContent?: IMCMediaContent = undefined;
  private mWriter?: IMCMediaContentWriter = undefined;
  private mSerialPromise = Promise.resolve();

  constructor(media: MCMedia, request: MCDownloadRequest) {
    super();
    this.mMedia = media;
    this.mRequest = request;
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Preparing loader for URL: ${this.mRequest.url}.`);

    const downloadRequest = new MCDownloadRequest(this.mRequest.url, this.mRequest.headers);
    if ( MCConfigs.requestHandler ) {
      MCConfigs.requestHandler(downloadRequest);
    }
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Download request created for URL: ${this.mRequest.url} with range: ${this.mRequest.rangeHeader}.`);

    this.mDownloadAbortController = new MCAbortController();
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Starting download for URL: ${this.mRequest.url}.`);
    MCDownload.download(downloadRequest, {
      headersReceive: (headers) => this.onHeadersReceive(headers),
      dataReceive: (data) => this.onDataReceive(data),
      dataEnd: () => this.onDataEnd(),
      signal: this.mDownloadAbortController.signal,
    }).then((res) => {
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Download completed for URL: ${this.mRequest.url}, Response headers: ${JSON.stringify(res.headers)}`);
      this.onComplete(res);
    }).catch((error: Error) => {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Http] Error during download for URL: ${this.mRequest.url} - ${(error as Error).message ?? ((error as BusinessError).code)}`);
      if ( this.mDownloadAbortController ) this.mDownloadAbortController = undefined;
      this.onError(error);
    });
  }

  private onHeadersReceive(headers: MCDownloadResponseHeaders): void { // 接收到headers的响应
    this.enqueueTask(() => new Promise(async (resolve) => {
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
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Http] Error processing headers for URL: ${this.mRequest.url} - ${(error as Error).message}. Stack trace: ${error.stack}`);
        this.onError(error);
      }
      finally {
        resolve();
      }
    }));
  }

  private onDataReceive(data: ArrayBuffer): void { // 接收到下载的数据
    this.enqueueTask(async () => {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Data received for URL: ${this.mRequest.url}. Bytes: ${data.byteLength}.`);

      if ( this.isAborted ) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Loader for URL: ${this.mRequest.url} is aborted. Ignoring data.`);
        return;
      }

      if ( !this.mContent || !this.mWriter ) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `[Http] Content or writer is undefined for URL: ${this.mRequest.url}.`);
        return;
      }

      try {
        const offset = this.mContent.contentOffset + this.mContent.length;
        if ( MCConfigs.dataEncryptHandler ) {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Encrypting data for URL: ${this.mRequest.url}. Offset: ${offset}, Bytes: ${data.byteLength}.`);
          await MCConfigs.dataEncryptHandler(this.mRequest, offset, data);
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Data encryption completed for URL: ${this.mRequest.url}. Offset: ${offset}, Bytes: ${data.byteLength}.`);
        }

        if ( this.isAborted ) {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Loader aborted after encrypting data for URL: ${this.mRequest.url}.`);
          return;
        }

        await this.mWriter.writeData(data, data.byteLength);
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Written ${data.byteLength} bytes to content for URL: ${this.mRequest.url}. Offset: ${offset}.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Http] Error writing data for URL: ${this.mRequest.url} - ${(error as Error).message}. Stack trace: ${error.stack}`);
        this.onError(error);
      }
    });
  }

  private onDataEnd(): void {
    this.mDownloadAbortController = undefined;
  }

  private async onComplete(res: MCDownload.Response): Promise<void> { // 下载完成后调用
    this.enqueueTask(async () => {
      if ( this.isAborted ) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Download aborted for URL: ${this.mRequest.url}. Completion process skipped.`);
        return;
      }

      if ( !this.mContent || !this.mContent.isTemp ) {
        return;
      }

      try {
        if ( res.statusCode !== 200 ) {
          throw new Error(`Expected 200 status code, but got ${res.statusCode}`);
        }

        await this.mMedia.finalize(this.mContent); // 临时内容下载完成, 交付转为正式内容;
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[Http] Temporary content finalized and stored for URL: ${this.mRequest.url}.`);

        if ( this.isAborted ) {
          throw new Error(`Loader aborted after copying temporary content.`);
        }

        const range = new MCRange(this.mContent.contentOffset, this.mContent.length);
        this.onPrepared(this.mContent, range); // 临时内容下载完成, 通知父类 onPrepared;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[Http] Error during onComplete for URL: ${this.mRequest.url} - ${error.message}. Stack trace: ${error.stack}`);
        this.onError(error);
      }
    });
  }

  protected async onClear(): Promise<void> { // 父类清理资源时调用
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[Http] Starting onClear for request: ${this.mRequest.url}. AbortController: ${this.mDownloadAbortController}, Content: ${this.mContent}, ContentWriter: ${this.mWriter}.`);

    if ( this.mDownloadAbortController ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Http] Aborting download.');
      this.mDownloadAbortController.abort();
      this.mDownloadAbortController = undefined;
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Http] Download aborted.');
    }

    const content = this.mContent;
    const writer = this.mWriter;

    if ( content ) {
      this.mContent = undefined;
      this.mWriter = undefined;

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Http] Closing content writer.');
      try {
        await writer?.close();
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Http] Content writer closed successfully.');
      }
      catch (error) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `[Http] Error closing writer for request: ${this.mRequest.url} - ${(error as Error).message}. Stack trace: ${error.stack}`);
      }

      if (content.isTemp) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Http] Destroying temporary content.');
        try {
          await this.mMedia.destroy(content);
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => '[Http] Temporary content destroyed successfully.');
        }
        catch (error) {
          MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `[Http] Error destroying temporary content for request: ${this.mRequest.url} - ${(error as Error).message}. Stack trace: ${error.stack}`);
        }
      }
    }
  }

  // 确保操作按顺序串行执行
  private enqueueTask(task: () => Promise<void>): void {
    this.mSerialPromise = this.mSerialPromise
      .catch((e: Error) => this.onError(e)) // 捕获上一个任务的异常，防止链断裂
      .then(() => task()); // 执行新任务
  }
}