import { IMCAsset } from "../defines/IMCAsset";
import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCHttpResponseHeaders } from "../defines/IMCHttpResponseHeaders";
import { MCLogModule } from "../defines/MCLogModule";
import { MCMediaDataFetcher } from "../media/MCMediaDataFetcher";
import MCLogger from "../utils/MCLogger";

export class MCAssetDataFetcher implements IMCDataFetcher {
  private mClientId: number;
  private mRequest: IMCDataRequest;
  private mAsset: IMCAsset;

  private mOnNewDataReadable?: (fetcher: IMCDataFetcher) => void = undefined;
  private mOnAborted?: (fetcher: IMCDataFetcher, error: Error) => void = undefined;

  private mDataEnd = false;
  private mAborted = false;
  private mError?: Error = undefined; // aborted 时必定有值;

  private mMediaDataFetcher?: IMCDataFetcher;

  constructor(clientId: number, asset: IMCAsset, request: IMCDataRequest) {
    this.mClientId = clientId;
    this.mAsset = asset;
    this.mRequest = request;

    asset.readwriteRetain();

    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Created fetcher for asset. Request: ${JSON.stringify(this.mRequest)}`);
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

  async prepare(): Promise<IMCHttpResponseHeaders> {
    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Starting preparation for asset request: ${JSON.stringify(this.mRequest)}`);

    try {
      const media = await this.mAsset.getMediaByProxyPath(this.mRequest.requestTarget);
      if ( this.mAborted ) {
        MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted`);
        throw this.mError!;
      }

      const fetcher = new MCMediaDataFetcher(this.mClientId, media, this.mRequest);
      this.mMediaDataFetcher = fetcher;
      MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Instantiated media fetcher`);

      this.mMediaDataFetcher.on('newDataReadable', () => this.onNewDataReadable());
      this.mMediaDataFetcher.on('aborted', (_, error) => this.onError(error));
      const responseHeaders = await this.mMediaDataFetcher.prepare();

      MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Preparation complete. Response headers: ${JSON.stringify(responseHeaders)}`);

      if ( fetcher.isDataEnd ) {
        this.done();
      }
      return responseHeaders;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Error during preparation: ${error.message}. Stack: ${error.stack}`);
      this.onError(error);
      throw this.mError ?? error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    const fetcher = this.mMediaDataFetcher;
    if ( !fetcher ) {
      MCLogger.warn(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Attempted to read but no media fetcher available`);
      return undefined;
    }

    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Starting read data. Offset: ${fetcher.offset}, Readable: ${fetcher.readableLength}`);

    const result = await fetcher.read(capacity);
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Read ${result?.byteLength ?? 0} bytes`);

    if ( fetcher.isDataEnd ) {
      this.done();
    }
    return result;
  }

  seek(offset: number): boolean {
    const fetcher = this.mMediaDataFetcher;
    if ( !fetcher ) {
      MCLogger.warn(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Attempted to seek but no media fetcher available`);
      return false;
    }

    const result = fetcher.seek(offset);
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Seek to offset ${offset} ${result ? "succeeded" : "failed"}`);

    if ( result && fetcher.isDataEnd ) {
      this.done();
    }
    return result;
  }

  abort(error?: Error | undefined): void {
    if ( this.isCompleted ) {
      MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Abort called but fetcher is already completed`);
      return;
    }

    this.mAborted = true;
    this.mError = error ?? new Error(`Fetcher was aborted`);

    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Aborting fetcher. Reason: ${this.mError!.message}, Stack: ${this.mError!.stack}`);

    const fetcher = this.mMediaDataFetcher;
    if ( fetcher ) {
      this.mMediaDataFetcher = undefined;
      fetcher.off("newDataReadable");
      fetcher.off("aborted");
      if ( !fetcher.isCompleted ) fetcher.abort(error);
    }

    this.mAsset.readwriteRelease();

    setTimeout(() => {
      MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${this.mError?.message}`);
      this.mOnAborted?.(this, this.mError!);
    })
  }

  private done(): void {
    if ( this.isCompleted ) {
      return;
    }

    this.mDataEnd = true;
    this.mAsset.readwriteRelease();

    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Data fetching complete. Marking as done`);
  }

  on(event: 'newDataReadable', callback: (fetcher: IMCDataFetcher) => void): void;
  on(event: 'aborted', callback: (fetcher: IMCDataFetcher, error: Error) => void): void;
  on(event: string, callback: Object): void {
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] ${event} callback registered`);

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
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] ${event} callback removed`);

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

    MCLogger.error(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Error encountered. Triggering abort. Error: ${error?.message}`);
    this.abort(error);
  }

  private onNewDataReadable(): void {
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] newDataReadable triggered. Invoking callback`);
    this.mOnNewDataReadable?.(this);
  }
}