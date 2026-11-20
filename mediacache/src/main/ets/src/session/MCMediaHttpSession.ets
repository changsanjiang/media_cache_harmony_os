import { IMCAsset } from '../defines/IMCAsset';
import { IMCDataFetcher } from '../defines/IMCDataFetcher';
import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCHttpResponseHeaders } from '../defines/IMCHttpResponseHeaders';
import { MCLogModule } from '../defines/MCLogModule';
import { MCMediaDataFetcher } from '../media/MCMediaDataFetcher';
import MCLogger from '../utils/MCLogger';

/**
 * 一次代理 HTTP 请求的会话层：Asset → Media → {@link MCMediaDataFetcher}。
 *
 * 生命周期：构造时 `asset.readwriteRetain()`，在 `done()` / `abort()` 时 release 一次。
 *
 * @see MCHttpResponse 对 `/mc_proxy`、`/mc_dir_proxy` 使用本类
 */
export class MCMediaHttpSession implements IMCDataFetcher {
  private mClientId: number;
  private mRequest: IMCDataRequest;
  private mAsset: IMCAsset;

  private mOnNewDataReadable?: (fetcher: IMCDataFetcher) => void = undefined;
  private mOnAborted?: (fetcher: IMCDataFetcher, error: Error) => void = undefined;

  private mDataEnd = false;
  private mAborted = false;
  private mError?: Error = undefined;

  private mMediaDataFetcher?: IMCDataFetcher;

  constructor(clientId: number, asset: IMCAsset, request: IMCDataRequest) {
    this.mClientId = clientId;
    this.mAsset = asset;
    this.mRequest = request;
    // 与 MCRequestScope 相同：会话存活期间计入 in-use，防止淘汰
    asset.readwriteRetain();
    MCLogger.info(MCLogModule.MCMediaHttpSession, () => `[clientId: ${this.mClientId}] Created HTTP session. Request: ${JSON.stringify(this.mRequest)}`);
  }

  get isReady(): boolean {
    return this.mMediaDataFetcher?.isReady ?? false;
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
    return this.mMediaDataFetcher?.offset ?? 0;
  }

  get readableLength(): number {
    return this.mMediaDataFetcher?.readableLength ?? 0;
  }

  /** 按 proxyPath 解析 Media，生成 HTTP 响应头（含 Range/长度）。 */
  async prepare(): Promise<IMCHttpResponseHeaders> {
    MCLogger.info(MCLogModule.MCMediaHttpSession, () => `[clientId: ${this.mClientId}] Starting preparation: ${JSON.stringify(this.mRequest)}`);
    try {
      const media = await this.mAsset.getMediaByProxyPath(this.mRequest.requestTarget);
      if ( this.mAborted ) {
        throw this.mError!;
      }

      const fetcher = new MCMediaDataFetcher(this.mClientId, media, this.mRequest);
      this.mMediaDataFetcher = fetcher;
      this.mMediaDataFetcher.on('newDataReadable', () => this.onNewDataReadable());
      this.mMediaDataFetcher.on('aborted', (_, error) => this.onError(error));
      const responseHeaders = await this.mMediaDataFetcher.prepare();

      if ( fetcher.isDataEnd ) {
        this.done();
      }
      return responseHeaders;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaHttpSession, () => `[clientId: ${this.mClientId}] Prepare failed: ${(error as Error).message}`);
      this.onError(error as Error);
      throw this.mError ?? error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    const fetcher = this.mMediaDataFetcher;
    if ( !fetcher ) {
      return undefined;
    }
    const result = await fetcher.read(capacity);
    if ( fetcher.isDataEnd ) {
      this.done();
    }
    return result;
  }

  seek(offset: number): boolean {
    const fetcher = this.mMediaDataFetcher;
    if ( !fetcher ) {
      return false;
    }
    const result = fetcher.seek(offset);
    if ( result && fetcher.isDataEnd ) {
      this.done();
    }
    return result;
  }

  /** 中止下游 MediaFetcher 并释放 Asset 引用。 */
  abort(error?: Error | undefined): void {
    if ( this.isCompleted ) {
      return;
    }
    this.mAborted = true;
    this.mError = error ?? new Error(`HTTP session aborted`);

    const fetcher = this.mMediaDataFetcher;
    if ( fetcher ) {
      this.mMediaDataFetcher = undefined;
      fetcher.off('newDataReadable');
      fetcher.off('aborted');
      if ( !fetcher.isCompleted ) {
        fetcher.abort(error);
      }
    }
    this.mAsset.readwriteRelease();
    setTimeout(() => this.mOnAborted?.(this, this.mError!));
  }

  /** 响应体读完：标记结束并释放 Asset 引用。 */
  private done(): void {
    if ( this.isCompleted ) {
      return;
    }
    this.mDataEnd = true;
    this.mAsset.readwriteRelease();
  }

  on(event: 'newDataReadable', callback: (fetcher: IMCDataFetcher) => void): void;
  on(event: 'aborted', callback: (fetcher: IMCDataFetcher, error: Error) => void): void;
  on(event: string, callback: Object): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = callback as (fetcher: IMCDataFetcher) => void;
        break;
      case 'aborted':
        this.mOnAborted = callback as (fetcher: IMCDataFetcher, error: Error) => void;
        break;
    }
  }

  off(event: 'newDataReadable'): void;
  off(event: 'aborted'): void;
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

  private onError(error?: Error): void {
    if ( this.isCompleted ) {
      return;
    }
    this.abort(error);
  }

  private onNewDataReadable(): void {
    this.mOnNewDataReadable?.(this);
  }
}