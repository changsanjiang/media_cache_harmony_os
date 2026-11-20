import MCLogger from '../utils/MCLogger';
import { IMCHttpRequest } from '../defines/IMCHttpRequest';
import { IMCHttpResponse } from '../defines/IMCHttpResponse';
import { MCLogModule } from '../defines/MCLogModule';
import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { IMCHttpOkResponseHeaders } from '../defines/IMCHttpResponseHeaders';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { MCHttpProxyRouter } from './MCHttpProxyRouter';
import { MCHttpWireFormat } from './MCHttpWireFormat';
import { MCHttpLog } from './MCHttpLog';

/** 将 {@link IMCDataFetcher} 适配为 {@link IMCHttpResponse}；路由与线格式委托 ProxyRouter / WireFormat。 */
export class MCHttpResponseAdapter implements IMCHttpResponse {
  private mClientId: number;
  private mRequest: IMCHttpRequest
  private mFetcher?: IMCDataFetcher = undefined;
  private mChunked = false;
  private mChunkReadEnd = false;

  private mAborted = false;
  private mDataEnd = false;
  private mError?: Error = undefined;

  private mOnNewDataReadable?: (response: IMCHttpResponse) => void = undefined;
  private mOnAborted?: (response: IMCHttpResponse, error: Error) => void = undefined;

  constructor(clientId: number, request: IMCHttpRequest) {
    this.mClientId = clientId;
    this.mRequest = request;
    MCLogger.debug(MCLogModule.MCHttpResponseAdapter, () => MCLogger.withClient(clientId, `Response adapter for ${MCHttpLog.summarizeRequest(request)}`));
  }

  get isReady(): boolean {
    return this.mFetcher?.isReady ?? false;
  }

  get isCompleted(): boolean {
    return this.mAborted || this.isDone;
  }

  get isDone(): boolean {
    return this.mDataEnd && (!this.mChunked || this.mChunkReadEnd);
  }

  get omitsResponseBody(): boolean {
    return this.mRequest.method === 'HEAD';
  }

  private toDataRequest(requestTarget: string): IMCDataRequest {
    const method = this.mRequest.method === 'HEAD' ? 'HEAD' : 'GET';
    return {
      requestTarget: requestTarget,
      headers: this.mRequest.headers,
      method: method
    };
  }

  async prepare(): Promise<string> {
    MCLogger.debug(MCLogModule.MCHttpResponseAdapter, () => MCLogger.withClient(this.mClientId, `prepare ${MCHttpLog.summarizeRequest(this.mRequest)}`));
    try {
      const requestTarget = await MCHttpProxyRouter.normalizeRequestTarget(this.mClientId, this.mRequest.requestTarget);
      const dataRequest = this.toDataRequest(requestTarget);

      this.mFetcher = await MCHttpProxyRouter.resolveFetcher(this.mClientId, requestTarget, dataRequest);

      if ( this.mAborted ) {
        MCLogger.debug(MCLogModule.MCHttpResponseAdapter, () => MCLogger.withClient(this.mClientId, 'prepare skipped (already aborted)'));
        throw this.mError!;
      }

      if ( !this.mFetcher ) {
        throw new Error(`[clientId: ${this.mClientId}] Data fetcher initialization failed — fetcher is undefined.`);
      }

      this.mFetcher.on('newDataReadable', () => this.onNewDataReadable());
      this.mFetcher.on('aborted', (_, error) => this.onError(error));

      const responseHeaders = await this.mFetcher.prepare();
      if ( this.mAborted ) {
        MCLogger.warn(MCLogModule.MCHttpResponseAdapter, () => `[clientId: ${this.mClientId}] Aborted after fetcher prepare. Reason: ${this.mError?.message}`);
        throw this.mError!;
      }

      this.mChunked = responseHeaders.statusCode === 200 && (responseHeaders as IMCHttpOkResponseHeaders).chunked === true;
      const rawHeaders = MCHttpWireFormat.formatResponseHeaders(responseHeaders, this.mClientId);

      MCLogger.info(MCLogModule.MCHttpResponseAdapter, () => MCLogger.withClient(this.mClientId,
        `prepare done status=${responseHeaders.statusCode} chunked=${this.mChunked} eos=${this.mFetcher?.isDataEnd}`));

      if ( this.mFetcher.isDataEnd ) {
        this.mDataEnd = true;
      }
      return rawHeaders;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpResponseAdapter, () => MCLogger.withClient(this.mClientId, `prepare failed: ${(error as Error).message}`));
      this.onError(error as Error);
      throw error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    if (capacity <= 0) {
      MCLogger.warn(MCLogModule.MCHttpResponseAdapter, () => MCLogger.withClient(this.mClientId, `invalid read capacity ${capacity}`));
      return undefined;
    }

    const fetcher = this.mFetcher;
    if ( fetcher == undefined ) return undefined;

    const data = await fetcher.read(capacity);

    if ( data ) {
      if ( fetcher.isDataEnd ) {
        this.mDataEnd = true;
      }

      if ( this.mChunked ) {
        return MCHttpWireFormat.wrapChunkedBody(data);
      }

      return data;
    }

    if ( this.mDataEnd && this.mChunked && !this.mChunkReadEnd ) {
      this.mChunkReadEnd = true;
      return MCHttpWireFormat.chunkedTerminator();
    }

    return data;
  }

  abort(error?: Error | undefined): void {
    if ( this.isCompleted ) {
      return;
    }

    this.mAborted = true;
    this.mError = error ?? new Error('Response was aborted');

    MCLogger.info(MCLogModule.MCHttpResponseAdapter, () => MCLogger.withClient(this.mClientId, `abort: ${this.mError!.message}`));

    const fetcher = this.mFetcher;
    if ( fetcher ) {
      this.mFetcher = undefined;
      fetcher.off('newDataReadable');
      fetcher.off('aborted');
      if ( !fetcher.isCompleted ) fetcher.abort(this.mError);
    }

    setTimeout(() => this.mOnAborted?.(this, this.mError!));
  }

  on(event: "newDataReadable", callback: (response: IMCHttpResponse) => void): void;
  on(event: "aborted", callback: (response: IMCHttpResponse, error: Error) => void): void;
  on(event: string, callback: Object): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = callback as (response: IMCHttpResponse) => void;
        break;
      case 'aborted':
        this.mOnAborted = callback as (response: IMCHttpResponse, error: Error) => void;
        break;
    }
  }

  off(event: "newDataReadable"): void;
  off(event: "aborted"): void;
  off(event: string): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = undefined;
        break;
      case 'aborted':
        this.mOnAborted = undefined;
        break;
    }
  }

  private onNewDataReadable(): void {
    this.mOnNewDataReadable?.(this);
  }

  private onError(error?: Error): void {
    if ( this.isCompleted ) {
      return;
    }

    this.abort(error);
  }
}