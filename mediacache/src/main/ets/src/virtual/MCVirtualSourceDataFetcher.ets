import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { parseRequestRange } from '../defines/IMCHttpRequestRange';
import {
  IMCHttpOkResponseHeaders,
  IMCHttpPartialContentResponseHeaders,
  IMCHttpResponseHeaders
} from '../defines/IMCHttpResponseHeaders';
import { IMCMediaContent } from '../defines/IMCMediaContent';
import { IMCMediaContentLoader } from '../defines/IMCMediaContentLoader';
import {
  IMCVirtualSource,
  IMCVirtualSourceBuffer,
  IMCVirtualSourceFile,
  IMCVirtualSourceType
} from '../defines/IMCVirtualSource';
import { MCLogModule } from '../defines/MCLogModule';
import { MCMediaContentLoaderState } from '../defines/MCMediaContentLoaderState';
import { MCMediaBufferContent } from '../media/MCMediaBufferContent';
import { MCMediaContent } from '../media/MCMediaContent';
import { MCMediaLocalContentLoader } from '../media/MCMediaLocalContentLoader';
import MCConfigs from '../utils/MCConfigs';
import MCFileIOUtils from '../utils/MCFileIOUtils';
import MCLogger from '../utils/MCLogger';
import { MCRange } from '../utils/MCRange';

export class MCVirtualSourceDataFetcher implements IMCDataFetcher {
  private mClientId: number;
  private mSource: IMCVirtualSourceType;
  private mRequest: IMCDataRequest;

  private mOnAborted: ((fetcher: IMCDataFetcher, error: Error) => void) | undefined = undefined;

  private mResponseHeaders: IMCHttpResponseHeaders | undefined = undefined;
  private mContentLoader: IMCMediaContentLoader | undefined = undefined;
  private mDataEnd = false;
  private mAborted = false;
  private mError: Error | undefined = undefined; // aborted 时必定有值;

  constructor(
    clientId: number,
    source: IMCVirtualSourceType,
    request: IMCDataRequest
  ) {
    this.mClientId = clientId;
    this.mSource = source;
    this.mRequest = request;

    MCLogger.info(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Created fechter for request: ${JSON.stringify(this.mRequest)}`);
  }

  get isReady(): boolean {
    return this.mResponseHeaders != undefined;
  }

  get isCompleted(): boolean {
    return this.mDataEnd || this.mAborted;
  }

  get isAborted(): boolean {
    return this.mAborted;
  }

  get isDataEnd(): boolean {
    return this.mDataEnd;
  }

  get offset(): number {
    return this.mContentLoader?.offset ?? 0;
  }

  get readableLength(): number {
    return this.mContentLoader?.readableLength ?? 0;
  }

  async prepare(): Promise<IMCHttpResponseHeaders> {
    MCLogger.info(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Starting preparation for request: ${JSON.stringify(this.mRequest)}}`);

    if ( this.mAborted ) {
      MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted`);
      throw this.mError!;
    }

    try {
      const content = await this.createContent();
      const mimeType = this.mSource.mimeType ?? 'application/octet-stream';
      const requestHeader = this.mRequest.headers?.['range'];
      const readRange = requestHeader ? parseRequestRange(requestHeader).toRange(content.length) : new MCRange(0, content.length);

      this.mContentLoader = new MCMediaLocalContentLoader(
        this.mClientId,
        0,
        content,
        readRange,
      );
      this.mContentLoader.on("stateChange", (loader, state) => {
        if ( state == MCMediaContentLoaderState.Aborted ) {
          this.onError(loader.error ?? new Error(`Content loader was aborted`));
        }
      });
      setTimeout(() => this.mContentLoader?.prepare());

      if ( requestHeader ) {
        const responseHeaders: IMCHttpPartialContentResponseHeaders = {
          statusCode: 206,
          contentType: mimeType,
          contentRange: readRange,
          totalLength: content.length,
        };
        this.mResponseHeaders = responseHeaders;
        return responseHeaders;
      }

      const responseHeaders: IMCHttpOkResponseHeaders = {
        statusCode: 200,
        contentType: mimeType,
        chunked: false,
        contentLength: content.length,
        byteRangeAccessSupported: true,
      };
      this.mResponseHeaders = responseHeaders;
      MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Generated response headers: ${JSON.stringify(responseHeaders)}`);

      return responseHeaders;
    }
    catch (error) {
      MCLogger.warn(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Fetch failed during prepare: ${error?.message}`);
      this.onError(error);
      throw error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    const contentLoader = this.mContentLoader;
    if ( contentLoader ) {

      const offset = contentLoader.offset;
      MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Attempting to read ${capacity} bytes at offset ${offset}`);

      let data = await contentLoader.read(capacity);
      MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Read ${data?.byteLength ?? 0} bytes`);

      if ( data ) {
        // 校验数据一致性
        if ( MCConfigs.dataValidationHandler ) {
          MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Validating data. Offset: ${offset}, Bytes: ${data?.byteLength}`);
          const result = await MCConfigs.dataValidationHandler(this.mRequest, offset, data);
          if ( !result ) {
            throw new Error(`Data validation failed at offset ${offset}. Data size: ${data.byteLength} bytes.`);
          }

          MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Data validation passed. Offset: ${offset}, Bytes: ${data?.byteLength}`);
        }

        // 数据解密
        if ( MCConfigs.dataDecryptionHandler ) {
          MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Decrypting data. Offset: ${offset}, Bytes: ${data?.byteLength}`);
          const byteLength = data.byteLength;
          const result = await MCConfigs.dataDecryptionHandler(this.mRequest, offset, data);
          if ( result instanceof ArrayBuffer ) {
            // 比较数据长度
            // 解密后的数据长度必须与原始数据长度一致
            if ( result.byteLength != byteLength ) {
              MCLogger.error(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Decrypted data length mismatch. Offset: ${offset}, OriginalBytes: ${byteLength}, DecryptedBytes: ${result.byteLength}`);
              throw new Error(`Decrypted data length mismatch at offset ${offset}`);
            }

            data = result;
          }
          MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Data decryption completed. Offset: ${offset}, Bytes: ${byteLength}`);
        }
      }

      if ( contentLoader.state == MCMediaContentLoaderState.Ended ) {
        MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Content loader has reached end`);

        this.done();
      }
      return data;
    }
    return undefined;
  }

  seek(offset: number): boolean {    
    const contentLoader = this.mContentLoader;
    if ( contentLoader ) {
      const rangeStart = contentLoader.offset;
      const rangeEnd = contentLoader.offset + contentLoader.readableLength;
      if ( offset < rangeStart || offset > rangeEnd ) {
        return false;
      }

      const result = contentLoader.seek(offset);
      MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Seek to offset ${offset} ${result ? "succeeded" : "failed"}.`);

      if ( result ) {
        if ( contentLoader.state == MCMediaContentLoaderState.Ended ) {
          MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Content loader has reached end`);

          this.done();
        }
      }
      return result;
    }
    return false;
  }

  abort(error?: Error | undefined): void {
    if ( this.mAborted || this.mDataEnd ) {
      MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Abort called but fetcher is already completed`);
      return;
    }

    MCLogger.info(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Aborting fetcher. Reason: ${this.mError!.message}, Stack: ${this.mError!.stack}`);
    this.mAborted = true;
    this.mError = error ?? new Error('Fetcher was aborted');


    const contentLoader = this.mContentLoader;
    if ( contentLoader ) {
      MCLogger.info(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Aborting content loader`);
      contentLoader.off("stateChange");
      if ( contentLoader.state != MCMediaContentLoaderState.Ended &&
           contentLoader.state != MCMediaContentLoaderState.Aborted ) {
        contentLoader.abort(this.mError);
      }
      this.mContentLoader = undefined;
    }

    setTimeout(() => {
      this.mOnAborted?.(this, this.mError!);
    });
  }

  private done(): void {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    MCLogger.info(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as done`);

    this.mDataEnd = true;
    this.mContentLoader?.off("stateChange");
    this.mContentLoader = undefined;
  }

  private onError(error: Error): void {
    if ( this.isCompleted ) {
      return;
    }
    this.abort(error);
  }

  on(event: "newDataReadable", callback: (fetcher: IMCDataFetcher) => void): void;
  on(event: "aborted", callback: (fetcher: IMCDataFetcher, error: Error) => void): void;
  on(event: string, callback: Object): void {
    MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] ${event} callback registered`);
    
    switch (event) {
      case "newDataReadable":
        break;
      case "aborted":
        this.mOnAborted = callback as (fetcher: IMCDataFetcher, error: Error) => void;
        break;
    }
  }

  off(event: "newDataReadable"): void;
  off(event: "aborted"): void;
  off(event: string): void {
    MCLogger.debug(MCLogModule.MCVirtualSourceDataFetcher, () => `[clientId: ${this.mClientId}] ${event} callback removed`);

    switch (event) {
      case "newDataReadable":
        break;
      case "aborted":
        this.mOnAborted = undefined;
        break;
    }
  }

  private async createContent(): Promise<IMCMediaContent> {
    const fileSource = this.asFileDataSource(this.mSource);
    if ( fileSource ) {
      const content = new MCMediaContent(
        'VIRTUAL',
        0,
        fileSource.filePath,
        await MCFileIOUtils.getFileSize(fileSource.filePath)
      );
      return content;
    }

    const bufferSource = this.asBufferDataSource(this.mSource);
    if ( bufferSource ) {
      const content = new MCMediaBufferContent(
        'VIRTUAL',
        0,
        bufferSource.buffer,
        false,
      );
      return content;
    }

    throw new Error(`Unknown IMCVirtualSource type: ${JSON.stringify(this.mSource)}`);
  }

  private asFileDataSource(source: IMCVirtualSource): IMCVirtualSourceFile | undefined {
    const sourceAsFile = source as IMCVirtualSourceFile;
    if ( sourceAsFile && typeof sourceAsFile.filePath === 'string' && sourceAsFile.filePath.length > 0 ) {
      return sourceAsFile;
    }
    return undefined;
  }

  private asBufferDataSource(source: IMCVirtualSource): IMCVirtualSourceBuffer | undefined {
    const sourceAsBuffer = source as IMCVirtualSourceBuffer;
    if ( sourceAsBuffer && sourceAsBuffer.buffer instanceof ArrayBuffer ) {
      return sourceAsBuffer;
    }
    return undefined;
  }
}