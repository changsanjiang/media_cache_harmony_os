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
  IMCVirtualResource,
  IMCVirtualResourceBuffer,
  IMCVirtualResourceFile,
  IMCVirtualResourceType
} from '../defines/IMCVirtualResource';
import { MCLogModule } from '../defines/MCLogModule';
import { MCMediaContentLoaderState } from '../defines/MCMediaContentLoaderState';
import { MCMediaBufferContent } from '../media/MCMediaBufferContent';
import { MCMediaContent } from '../media/MCMediaContent';
import { MCMediaLocalContentLoader } from '../media/MCMediaLocalContentLoader';
import MCConfigs from '../utils/MCConfigs';
import MCFileIOUtils from '../utils/MCFileIOUtils';
import MCLogger from '../utils/MCLogger';
import { MCRange } from '../utils/MCRange';

export class MCVirtualResourceDataFetcher implements IMCDataFetcher {
  private mClientId: number;
  private mResource: IMCVirtualResourceType;
  private mRequest: IMCDataRequest;

  private mOnAborted: ((fetcher: IMCDataFetcher, error: Error) => void) | undefined = undefined;

  private mResponseHeaders: IMCHttpResponseHeaders | undefined = undefined;
  private mContentLoader: IMCMediaContentLoader | undefined = undefined;
  private mDataEnd = false;
  private mAborted = false;
  private mError: Error | undefined = undefined; // aborted 时必定有值;

  constructor(
    clientId: number,
    resource: IMCVirtualResourceType,
    request: IMCDataRequest
  ) {
    this.mClientId = clientId;
    this.mResource = resource;
    this.mRequest = request;

    MCLogger.info(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Created fechter for request: ${JSON.stringify(this.mRequest)}`);
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
    MCLogger.info(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Starting preparation for request: ${JSON.stringify(this.mRequest)}}`);

    if ( this.mAborted ) {
      MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted`);
      throw this.mError!;
    }

    try {
      const content = await this.createContent();
      const mimeType = this.mResource.mimeType ?? 'application/octet-stream';
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
      MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Generated response headers: ${JSON.stringify(responseHeaders)}`);

      return responseHeaders;
    }
    catch (error) {
      MCLogger.warn(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Fetch failed during prepare: ${error?.message}`);
      this.onError(error);
      throw error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    const contentLoader = this.mContentLoader;
    if ( contentLoader ) {

      const offset = contentLoader.offset;
      MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Attempting to read ${capacity} bytes at offset ${offset}`);

      let data = await contentLoader.read(capacity);
      MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Read ${data?.byteLength ?? 0} bytes`);

      if ( data ) {
        // 校验数据一致性
        if ( MCConfigs.dataValidationHandler ) {
          MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Validating data. Offset: ${offset}, Bytes: ${data?.byteLength}`);
          const result = await MCConfigs.dataValidationHandler(this.mRequest, offset, data);
          if ( !result ) {
            throw new Error(`Data validation failed at offset ${offset}. Data size: ${data.byteLength} bytes.`);
          }

          MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Data validation passed. Offset: ${offset}, Bytes: ${data?.byteLength}`);
        }

        // 数据解密
        if ( MCConfigs.dataDecryptionHandler ) {
          MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Decrypting data. Offset: ${offset}, Bytes: ${data?.byteLength}`);
          const byteLength = data.byteLength;
          const result = await MCConfigs.dataDecryptionHandler(this.mRequest, offset, data);
          if ( result instanceof ArrayBuffer ) {
            // 比较数据长度
            // 解密后的数据长度必须与原始数据长度一致
            if ( result.byteLength != byteLength ) {
              MCLogger.error(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Decrypted data length mismatch. Offset: ${offset}, OriginalBytes: ${byteLength}, DecryptedBytes: ${result.byteLength}`);
              throw new Error(`Decrypted data length mismatch at offset ${offset}`);
            }

            data = result;
          }
          MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Data decryption completed. Offset: ${offset}, Bytes: ${byteLength}`);
        }
      }

      if ( contentLoader.state == MCMediaContentLoaderState.Ended ) {
        MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Content loader has reached end`);

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
      MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Seek to offset ${offset} ${result ? "succeeded" : "failed"}.`);

      if ( result ) {
        if ( contentLoader.state == MCMediaContentLoaderState.Ended ) {
          MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Content loader has reached end`);

          this.done();
        }
      }
      return result;
    }
    return false;
  }

  abort(error?: Error | undefined): void {
    if ( this.mAborted || this.mDataEnd ) {
      MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Abort called but fetcher is already completed`);
      return;
    }

    MCLogger.info(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Aborting fetcher. Reason: ${this.mError!.message}, Stack: ${this.mError!.stack}`);
    this.mAborted = true;
    this.mError = error ?? new Error('Fetcher was aborted');


    const contentLoader = this.mContentLoader;
    if ( contentLoader ) {
      MCLogger.info(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Aborting content loader`);
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

    MCLogger.info(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as done`);

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
    MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] ${event} callback registered`);
    
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
    MCLogger.debug(MCLogModule.MCVirtualResourceDataFetcher, () => `[clientId: ${this.mClientId}] ${event} callback removed`);

    switch (event) {
      case "newDataReadable":
        break;
      case "aborted":
        this.mOnAborted = undefined;
        break;
    }
  }

  private async createContent(): Promise<IMCMediaContent> {
    const fileRes = this.asFileResource(this.mResource);
    if ( fileRes ) {
      const content = new MCMediaContent(
        'VIRTUAL',
        0,
        fileRes.filePath,
        await MCFileIOUtils.getFileSize(fileRes.filePath)
      );
      return content;
    }

    const bufRes = this.asBufferResource(this.mResource);
    if ( bufRes ) {
      const content = new MCMediaBufferContent(
        'VIRTUAL',
        0,
        bufRes.buffer,
        false,
      );
      return content;
    }

    throw new Error(`Unknown IMCVirtualResource type: ${JSON.stringify(this.mResource)}`);
  }

  private asFileResource(resource: IMCVirtualResource): IMCVirtualResourceFile | undefined {
    const resAsFile = resource as IMCVirtualResourceFile;
    if ( resAsFile && typeof resAsFile.filePath === 'string' && resAsFile.filePath.length > 0 ) {
      return resAsFile;
    }
    return undefined;
  }

  private asBufferResource(resource: IMCVirtualResource): IMCVirtualResourceBuffer | undefined {
    const resAsBuf = resource as IMCVirtualResourceBuffer;
    if ( resAsBuf && resAsBuf.buffer instanceof ArrayBuffer ) {
      return resAsBuf;
    }
    return undefined;
  }
}