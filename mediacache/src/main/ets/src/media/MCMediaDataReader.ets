import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCMedia } from "../defines/IMCMedia";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { IMCDataReader } from "../defines/IMCDataReader";
import {
  IMCDataOkResponse,
  IMCDataPartialContentResponse,
  IMCDataResponse, MCDataResponseStatusCode } from "../defines/IMCDataResponse";
import MCLogger from "../utils/MCLogger";
import MCAssetManager from "../asset/MCAssetManager";
import { ArkTSUtils } from "@kit.ArkTS";
import { MCRange } from "../utils/MCRange";
import { generateResponseContentRange } from "../defines/IMCHttpResponseContentRange";
import { MCLogModule } from "../defines/MCLogModule";
import { MCDataDecryptHandler } from "../defines/MCDataDecryptHandler";

export class MCMediaDataReader implements IMCDataReader {
  private mClientId: number;
  private mProxyRequest: IMCHttpRequest;
  private mDecrypt?: MCDataDecryptHandler;
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mMedia?: IMCMedia = undefined;
  private mIndex = -1;
  private mLoaders: IMCMediaContentLoader[] = [];
  private mDone = false;
  private mAborted = false;
  private mResponseReadyCallback?: (reader: IMCDataReader, response: IMCDataResponse) => void = undefined;
  private mNewDataReadableCallback?: (reader: IMCDataReader) => void = undefined;
  private mAbortedCallback?: (reader: IMCDataReader, error?: Error | undefined) => void = undefined;
  private mDoneCallback?: (reader: IMCDataReader) => void = undefined;
  private mResponse?: IMCDataResponse = undefined;
  private mOffset = 0;

  constructor(clientId: number, proxyRequest: IMCHttpRequest, decrypt?: MCDataDecryptHandler) {
    this.mClientId = clientId;
    this.mProxyRequest = proxyRequest;
    this.mDecrypt = decrypt;
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
  get response(): Promise<IMCDataResponse | undefined> {
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
      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Starting preparation.`);
      try {
        if (this.mAborted) {
          MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Cannot prepare as the reader has been aborted.`);
          return;
        }
        const media = await MCAssetManager.getMediaBy(this.mProxyRequest.requestTarget); // media readwrite retained, should release after;
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
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Attempting to read data into buffer of size: ${buffer.byteLength}.`);
      try {
        if (this.mDone || this.mAborted || !this.mResponse) {
          MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Cannot read data. Status - Done: ${this.mDone}, Aborted: ${this.mAborted}, Response: ${this.mResponse}.`);
          return 0;
        }
        const loader = this.mLoaders[this.mIndex];
        if (!loader) {
          throw new Error(`No valid loader available at index ${this.mIndex}`);
        }

        const len = await loader.readData(buffer);
        MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader read ${len} bytes of data at index ${this.mIndex}.`);

        if (len > 0) {
          // Handle decryption if applicable
          if (this.mDecrypt) {
            const decryptedLength = await this.mDecrypt(this.mProxyRequest, this.mOffset, buffer, len);
            // 解密后的数据长度不能发生改变;
            if (decryptedLength !== len) {
              throw new Error(`Decryption failed: expected ${len} bytes, but got ${decryptedLength} bytes.`);
            }
            MCLogger.trace(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Successfully decrypted ${decryptedLength} bytes.`);
          }
          this.mOffset += len;
          MCLogger.trace(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Read ${len} bytes. Updated offset: ${this.mOffset}.`);
        }
        else {
          MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] No data read. Buffer remains unchanged.`);
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
      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Starting seek to the end of the readable range.`);

      try {
        if (this.mDone || this.mAborted || !this.mResponse) {
          MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Seek operation aborted. Status - Done: ${this.mDone}, Aborted: ${this.mAborted}, Response: ${this.mResponse}.`);
          return 0;
        }
        // Ensure a valid loader is present
        const loader = this.mLoaders[this.mIndex];
        if (!loader) {
          throw new Error(`No valid loader found at index ${this.mIndex}.`);
        }

        const len = await loader.seekToEndOfReadableRange();
        MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader at index ${this.mIndex} seeked ${len} bytes.`);

        if (len > 0) {
          this.mOffset += len;
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Updated offset after seeking: ${this.mOffset}.`);
        }
        else {
          MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] No bytes skipped during seek. Loader may already be at the end of the readable range.`);
        }
        return len;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Error during seek operation: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mLock.lockAsync(() => this.abortUnsafe(error));
  }

  on(event: 'responseReady' | 'newDataReadable' | 'aborted' | 'done', callback: Object): Promise<void> {
    return this.mLock.lockAsync(() => {
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Registering callback for event '${event}'.`);

      switch (event) {
        case "responseReady":
          this.mResponseReadyCallback = callback as (reader: IMCDataReader, response: IMCDataResponse) => void;
          break;
        case "newDataReadable":
          this.mNewDataReadableCallback = callback as (reader: IMCDataReader) => void;
          break;
        case "aborted":
          this.mAbortedCallback = callback as (reader: IMCDataReader, error?: Error | undefined) => void;
          break;
        case "done":
          this.mDoneCallback = callback as (reader: IMCDataReader) => void;
          break;
      }
    });
  }

  off(event: 'responseReady' | 'newDataReadable' | 'aborted' | 'done'): Promise<void> {
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
        case "done":
          this.mDoneCallback = undefined;
          break;
      }
    });
  }

  private prepareNextLoader(): Promise<void> {
    return this.mLock.lockAsync(async () => {
      MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Preparing next loader.`);

      if (this.mAborted || this.mDone) {
        MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Attempted to prepare next loader, but the reader is either aborted or completed.`);
        return;
      }

      try {
        if (this.mLoaders.length === 0) {
          throw new Error(`No loaders available to prepare.`);
        }

        // 清理旧的 loader
        if (this.mIndex !== -1) {
          const loader = this.mLoaders[this.mIndex];
          const isDone = await loader.isDone;
          if ( !isDone ) {
            throw new Error(`Current loader at index ${this.mIndex} is not done yet.`);
          }
          MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Clearing completed loader at index ${this.mIndex}.`);
          this.clear(this.mLoaders[this.mIndex]);
        }

        let nextIndex = this.mIndex === -1 ? 0 : (this.mIndex + 1);
        if ( nextIndex === this.mLoaders.length ) {
          this.mDone = true;
          MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] All loaders completed. Marking reader as done.`);
          this.mMedia?.readwriteRelease();
          Promise.resolve(this.mDoneCallback).then((callback) => {
            if ( callback ) MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Executing done callback.`);
            callback?.(this);
          });
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
            if ( callback ) {
              MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Data loaded. Executing callback.`);
              callback(this);
            }
          });
        });

        loader.on("aborted", (_: IMCMediaContentLoader, error?: Error) => {
          MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader aborted at index ${nextIndex}. Error: ${error?.message || "None"}`);
          this.abort(error);
        });

        loader.on("done", () => {
          MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader at index ${nextIndex} has completed. Preparing the next loader.`);
          this.mLock.lockAsync(() => {
            this.prepareNextLoader();
          });
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
    loader.off('done');
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
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Aborting active loader at index ${this.mIndex}.`);
      loader.abort(error);
      this.clear(loader);
      MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Active loader cleared.`);
    }

    this.mMedia?.readwriteRelease();

    Promise.resolve(this.mAbortedCallback).then((callback) => {
      if ( callback ) MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
      callback?.(this, error);
    });
  }

  // loader 准备好后的回调;
  // reader 中可能会有多个 loader 串行加载数据, 当读取完前一个 loader 的数据后, 会准备读取下一个 loader 的数据;
  private onLoaderPrepared(loader: IMCMediaContentLoader, range: MCRange): void {
    this.mLock.lockAsync(async () => {
      try {
        if (this.mAborted || !this.mMedia) {
          MCLogger.warn(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Loader preparation skipped: Reader aborted or media unavailable.`);
          return;
        }

        // 正确的情况下 loader 之间的范围是连续的, 偏移量应该正好是下一个 loader 的起始位置;
        // Ensure the loader's range matches expected offset
        if (this.mResponse && this.mOffset !== range.location) {
          throw new Error(`Loader range mismatch: expected offset ${this.mOffset}, got ${range.location}.`);
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
          MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Initializing response for loader at range [${range.location}, ${range.location + range.length - 1}].`);

          const contentType = await this.mMedia.contentType;
          if (!contentType) {
            const errorMsg = `Content type is undefined for media.`;
            MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] ${errorMsg}`);
            throw new Error(errorMsg);
          }

          this.mOffset = range.location; // 设置响应数据的起始位置;
          const totalLength = await this.mMedia.totalLength;
          const requestRangeHeader = this.mProxyRequest.headers["range"];

          // 假设所有服务器都支持范围请求
          // Generate response based on the presence of a range header
          if (totalLength !== 0 && requestRangeHeader) {
            // Partial content response (206)
            const contentRange = generateResponseContentRange(requestRangeHeader, totalLength);
            if (contentRange.rangeStart !== range.location) { // 根据上面列出的前提, 请求的起始位置必须规范不能越界或参数错误;
              throw new Error(`Invalid range start: expected ${range.location}, got ${contentRange.rangeStart}.`);
            }

            const contentOffset = contentRange.rangeStart;
            const contentLength = contentRange.rangeEnd + 1 - contentRange.rangeStart;
            const response: IMCDataPartialContentResponse = {
              statusCode: MCDataResponseStatusCode.PARTIAL_CONTENT,
              contentType: contentType,
              contentOffset: contentOffset,
              contentLength: contentLength,
              totalLength: totalLength
            };
            this.mResponse = response;
            MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Partial content response prepared. Offset: ${response.contentOffset}, Length: ${response.contentLength}, Total: ${totalLength}.`);
          }
          else {
            // Full content response (200)
            const response: IMCDataOkResponse = {
              statusCode: MCDataResponseStatusCode.OK,
              contentType: contentType,
              contentLength: totalLength,
              byteRangeAccessSupported: true,
            };
            this.mResponse = response;

            if (totalLength === 0) {
              this.mDone = true;
              MCLogger.info(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Media has no content. Marking reader as done.`);
              this.clear(this.mLoaders[this.mIndex]);
              this.mMedia?.readwriteRelease();
            }
          }

          // Trigger response ready callback
          Promise.resolve(this.mResponseReadyCallback).then((callback) => {
            if (callback) {
              MCLogger.debug(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Response prepared. Executing callback.`);
              callback(this, this.mResponse!);
            }
          });
        }
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaDataReader, () => `[clientId: ${this.mClientId}] Error during loader preparation: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }
}