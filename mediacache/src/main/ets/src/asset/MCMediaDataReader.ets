import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { IMCMediaDataReader } from "../defines/IMCMediaDataReader";
import {
  IMCMediaDataOkResponse,
  IMCMediaDataPartialContentResponse,
  IMCMediaDataResponse, MCMediaDataResponseType } from "../defines/IMCMediaDataResponse";
import MCLogger from "../utils/MCLogger";
import MCAssetManager from "./MCAssetManager";
import { ArkTSUtils } from "@kit.ArkTS";
import { MCRange } from "../utils/MCRange";
import { generateResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { MCLogModule } from "../defines/MCLogModule";

export class MCMediaDataReader implements IMCMediaDataReader {
  private mClientId: number;
  private mProxyRequest: IMCHttpRequest;
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mMedia?: IMCMedia = undefined;
  private mIndex = -1;
  private mLoaders: IMCMediaContentLoader[] = [];
  private mDone = false;
  private mAborted = false;
  private mResponseReadyCallback?: (reader: IMCMediaDataReader, response: IMCMediaDataResponse) => void = undefined;
  private mNewDataReadableCallback?: (reader: IMCMediaDataReader) => void = undefined;
  private mAbortedCallback?: (reader: IMCMediaDataReader, error?: Error | undefined) => void = undefined;
  private mResponse?: IMCMediaDataResponse = undefined;
  private mOffset = 0;

  constructor(clientId: number, proxyRequest: IMCHttpRequest) {
    this.mClientId = clientId;
    this.mProxyRequest = proxyRequest;
    MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Instance created with request target: ${proxyRequest.requestTarget}`);
  }

  // 当前已准备好的可进行读取的数据的长度;
  get readableLength(): Promise<number> {
    return this.mLock.lockAsync(() => {
      if (this.mAborted || this.mDone || !this.mResponse) {
        return 0;
      }
      const loader = this.mLoaders[this.mIndex];
      return loader.readableLength;
    })
  }
  get response(): Promise<IMCMediaDataResponse | undefined> {
    return this.mLock.lockAsync(() => this.mResponse);
  }
  get isDone(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mDone);
  }
  get isAborted(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAborted);
  }

  // 获取media进行读取;
  prepare(): Promise<void> {
    return this.mLock.lockAsync(async () => {
      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Preparing media for reading.`);
      try {
        if (this.mAborted) {
          MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Cannot prepare as the reader has been aborted.`);
          return;
        }
        const media = await MCAssetManager.getMediaBy(this.mProxyRequest.requestTarget);
        await media.readwriteRetain();
        this.mMedia = media;
        this.mLoaders = await media.getContentLoadersBy(this.mProxyRequest);
        MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] ${this.mLoaders.length} content loaders initialized.`);
        this.prepareNextLoader();
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Failed to prepare media: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  readData(buffer: ArrayBuffer): Promise<number> {
    return this.mLock.lockAsync(async () => {
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Reading data into buffer of size: ${buffer.byteLength}.`);
      try {
        if (this.mDone || this.mAborted || !this.mResponse) {
          MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Cannot read data. Done: ${this.mDone}, Aborted: ${this.mAborted}, Response: ${this.mResponse}.`);
          return 0;
        }
        const loader = this.mLoaders[this.mIndex];
        const len = await loader.readData(buffer);
        if (len > 0) {
          this.mOffset += len;
          MCLogger.trace(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Read ${len} bytes. Current offset: ${this.mOffset}.`);
          if (await loader.isDone) {
            MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Current loader finished. Preparing next loader.`);
            this.prepareNextLoader();
          }
        }
        return len;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Error during data read: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  // 跳转到当前可读范围的尾部，并返回跳转了的长度(readableLength);
  seekToEndOfReadableRange(): Promise<number> {
    return this.mLock.lockAsync(async () => {
      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Seeking to end of readable range.`);
      try {
        if (this.mDone || this.mAborted || !this.mResponse) {
          MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Cannot seek. Done: ${this.mDone}, Aborted: ${this.mAborted}.`);
          return 0;
        }
        const loader = this.mLoaders[this.mIndex];
        const len = await loader.seekToEndOfReadableRange();
        if (len > 0) {
          this.mOffset += len;
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Seeked ${len} bytes. Current offset: ${this.mOffset}.`);
          if (await loader.isDone) {
            MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Current loader finished. Preparing next loader.`);
            this.prepareNextLoader();
          }
        }
        return len;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Error during seek: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mLock.lockAsync(() => this.abortUnsafe(error));
  }

  on(event: 'responseReady' | 'newDataReadable' | 'aborted', callback: Object): Promise<void> {
    return this.mLock.lockAsync(() => {
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Registering callback for event '${event}'.`);

      switch (event) {
        case "responseReady":
          this.mResponseReadyCallback = callback as (reader: IMCMediaDataReader, response: IMCMediaDataResponse) => void;
          break;
        case "newDataReadable":
          this.mNewDataReadableCallback = callback as (reader: IMCMediaDataReader) => void;
          break;
        case "aborted":
          this.mAbortedCallback = callback as (reader: IMCMediaDataReader, error?: Error | undefined) => void;
          break;
      }
    });
  }

  off(event: 'responseReady' | 'newDataReadable' | 'aborted'): Promise<void> {
    return this.mLock.lockAsync(() => {
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Removing callback for event '${event}'.`);

      switch (event) {
        case "responseReady":
          this.mResponseReadyCallback = undefined;
          break;
        case "newDataReadable":
          this.mNewDataReadableCallback = undefined;
          break;
        case "aborted":
          this.mAbortedCallback = undefined;
          break;
      }
    });
  }

  private prepareNextLoader(): Promise<void> {
    return this.mLock.lockAsync(async () => {
      if (this.mAborted || this.mDone) {
        MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Attempted to prepare next loader, but the reader is either aborted or completed.`);
        return;
      }

      try {
        if (this.mLoaders.length === 0) {
          const errorMsg = `No loaders available to prepare.`;
          MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] ${errorMsg}`);
          throw new Error(errorMsg);
        }

        // 清理旧的 loader
        if (this.mIndex !== -1) {
          const loader = this.mLoaders[this.mIndex];
          const isDone = await loader.isDone;
          if ( !isDone ) {
            const errorMsg = `Current loader at index ${this.mIndex} is not done yet.`;
            MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] ${errorMsg}`);
            throw new Error(errorMsg);
          }
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Clearing completed loader at index ${this.mIndex}.`);
          this.clear(this.mLoaders[this.mIndex]);
        }

        let nextIndex = this.mIndex === -1 ? 0 : (this.mIndex + 1);
        if ( nextIndex === this.mLoaders.length ) {
          this.mDone = true;
          MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] All loaders completed. Marking reader as done.`);
          this.mMedia?.readwriteRelease();
          return;
        }

        // 准备下一个loader
        this.mIndex = nextIndex;
        const loader = this.mLoaders[nextIndex];
        MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Preparing next loader at index ${nextIndex}.`);

        loader.on("prepared", (loader: IMCMediaContentLoader, range: MCRange) => {
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader prepared event received for index ${nextIndex}.`);
          this.onLoaderPrepared(loader, range);
        });

        loader.on("dataLoaded", (_: IMCMediaContentLoader, __: number) => {
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Data loaded event received for loader at index ${nextIndex}.`);
          this.mLock.lockAsync(() => this.mNewDataReadableCallback).then((callback) => {
            if ( callback ) MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Data loaded. Executing callback.`);
            callback?.(this);
          });
        });

        loader.on("aborted", (_: IMCMediaContentLoader, error?: Error) => {
          const errorMsg = `Loader aborted at index ${nextIndex}.`;
          MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] ${errorMsg} Error: ${error?.message || "None"}`);
          this.abort(error);
        });

        await loader.prepare();
        MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader at index ${nextIndex} is now prepared.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Failed to prepare next loader. Error: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  private clear(loader: IMCMediaContentLoader) {
    MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Clearing loader event listeners.`);

    loader.off('prepared');
    loader.off('dataLoaded');
    loader.off('aborted');
  }

  private async abortUnsafe(error?: Error): Promise<void> {
    if ( this.mAborted ) {
      return;
    }

    MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Aborting MCMediaDataReader${error ? ` due to error: ${error.message}` : ""}.`);

    this.mAborted = true;
    MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Reader marked as aborted.`);

    if (this.mIndex !== -1) {
      const loader = this.mLoaders[this.mIndex];
      loader.abort(error);
      this.clear(loader);
    }
    this.mMedia?.readwriteRelease();
    Promise.resolve(this.mAbortedCallback).then((callback) => {
      if ( callback ) MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Executing aborted callback.`);
      callback?.(this, error);
    });
  }

  // loader 准备好后的回调;
  // reader 中可能会有多个 loader 串行加载数据, 当读取完前一个 loader 的数据后, 会准备读取下一个 loader 的数据;
  private onLoaderPrepared(loader: IMCMediaContentLoader, range: MCRange): void {
    this.mLock.lockAsync(async () => {
      try {
        if (this.mAborted || !this.mMedia) {
          return;
        }

        if (this.mResponse && this.mOffset !== range.location) {
          // 正确的情况下 loader 之间的范围是连续的, 偏移量应该正好是下一个 loader 的起始位置;
          const errorMsg = `Loader range mismatch: expected offset ${this.mOffset}, got ${range.location}.`;
          MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] ${errorMsg}`);
          throw new Error(errorMsg);
        }

        // 如何生成响应?
        // 这里需要一些前提:
        //  - 假设所有服务器都支持范围请求;
        //  - 假设所有请求都严格遵守规范:
        //    - 客户端发起 200 请求时, 请求参数中不能包含范围参数;
        //    - 客户端发起 206 请求时, 请求中的范围参数不会越界;
        //
        // 根据以上前提生成响应
        //
        // 如果 response 未设置, 这里的 loader 必定是首个加载器, 此时准备生成响应;
        if (!this.mResponse) {
          const contentType = await this.mMedia.contentType;
          if (!contentType) {
            const errorMsg = `Content type is undefined for media.`;
            MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] ${errorMsg}`);
            throw new Error(errorMsg);
          }

          this.mOffset = range.location; // 设置响应数据的起始位置;
          const totalLength = await this.mMedia.totalLength;
          const requestRangeHeader = this.mProxyRequest.headers['range'];

          // 为 206 请求生成响应;
          if ( totalLength !== 0 && requestRangeHeader ) {
            const contentRange = generateResponseContentRange(requestRangeHeader, totalLength);
            if ( contentRange.rangeStart != range.location ) { // 根据上面列出的前提, 请求的起始位置必须规范不能越界或参数错误;
              const errorMsg = `Invalid range start: expected ${range.location}, got ${contentRange.rangeStart}.`;
              MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] ${errorMsg}`);
              throw new Error(errorMsg);
            }

            const contentOffset = contentRange.rangeStart;
            const contentLength = contentRange.rangeEnd + 1 - contentRange.rangeStart;
            const response: IMCMediaDataPartialContentResponse = {
              type: MCMediaDataResponseType.PARTIAL_CONTENT,
              contentType: contentType,
              contentOffset: contentOffset,
              contentLength: contentLength,
              totalLength: totalLength
            };
            this.mResponse = response;
          }
          // 为 200 请求生成响应;
          else {
            const contentLength = totalLength;
            const response: IMCMediaDataOkResponse = {
              type: MCMediaDataResponseType.OK,
              contentType: contentType,
              contentLength: contentLength,
              byteRangeAccessSupported: true,
            };
            this.mResponse = response;

            if (totalLength === 0) { // empty content;
              this.mDone = true;
              MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Empty content. Marking reader as done.`);
              this.clear(this.mLoaders[this.mIndex]);
              this.mMedia?.readwriteRelease();
            }
          }

          Promise.resolve(this.mResponseReadyCallback).then((callback) => {
            if ( callback ) MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Response prepared. Executing callback.`);
            callback?.(this, this.mResponse!);
          });
        }
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Error during loader preparation: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    })
  }
}