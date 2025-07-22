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
  private mOnAborted?: (fetcher: IMCDataFetcher, error?: Error | undefined) => void = undefined;
  private mOnDataEnd?: (fetcher: IMCDataFetcher) => void = undefined;

  private mDataEnd = false;
  private mAborted = false;
  private mError?: Error = undefined; // aborted 时必定有值;

  private mMediaDataFetcher?: IMCDataFetcher;

  constructor(clientId: number, asset: IMCAsset, request: IMCDataRequest) {
    this.mClientId = clientId;
    this.mAsset = asset;
    this.mRequest = request;

    asset.readwriteRetain();

    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Instance created for request: ${JSON.stringify(this.mRequest)}}`);
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
    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Preparing asset reader for request: ${JSON.stringify(this.mRequest)}}`);
    try {
      const media = await this.mAsset.getMediaBy(this.mRequest.requestTarget);
      if ( this.mAborted ) {
        MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted.`);
        throw this.mError!;
      }
      this.mMediaDataFetcher = new MCMediaDataFetcher(this.mClientId, media, this.mRequest);
      this.mMediaDataFetcher.on('newDataReadable', () => this.onNewDataReadable());
      this.mMediaDataFetcher.on('aborted', (_, error) => this.onError(error));
      this.mMediaDataFetcher.on('dataEnd', () => this.done());
      return this.mMediaDataFetcher.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Error during asset reader preparation: ${error.message}. Stack trace: ${error.stack}`);
      this.onError(error);
      throw this.mError ?? error as Error;
    }
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    const result = await this.mMediaDataFetcher?.read(capacity) ?? undefined;
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Read ${result?.byteLength ?? 0} bytes.`);
    return result;
  }

  seek(offset: number): boolean {
    const result = this.mMediaDataFetcher?.seek(offset) ?? false;
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Seek to offset ${offset} ${result ? "succeeded" : "failed"}.`);
    return result;
  }

  abort(error?: Error | undefined): void {
    if ( this.isCompleted ) {
      return;
    }

    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Aborting fetcher${error ? ` due to error: ${error.message}` : ""}. Stack trace: ${error?.stack || 'none'}`);

    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as aborted.`);

    this.mAborted = true;
    this.mError = error ?? new Error(`Fetcher was aborted`);

    const fetcher = this.mMediaDataFetcher;
    if ( fetcher ) {
      this.mMediaDataFetcher = undefined;
      fetcher.off("newDataReadable");
      fetcher.off("aborted");
      fetcher.off("dataEnd");
      if ( !fetcher.isCompleted ) fetcher.abort(error);
    }

    this.mAsset.readwriteRelease();

    Promise.resolve().then(() => {
      MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${this.mError?.message}.`);
      this.mOnAborted?.(this, this.mError);
    })
  }

  private done(): void {
    if ( this.isCompleted ) {
      return;
    }

    this.mDataEnd = true;
    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as done.`);
    this.mAsset.readwriteRelease();

    Promise.resolve().then(() => {
      MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Executing dataEnd callback.`);
      this.mOnDataEnd?.(this);
    })
  }

  on(event: 'newDataReadable', callback: (fetcher: IMCDataFetcher) => void): void;
  on(event: 'aborted', callback: (fetcher: IMCDataFetcher, error?: Error) => void): void;
  on(event: 'dataEnd', callback: (fetcher: IMCDataFetcher) => void): void;
  on(event: string, callback: Object): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = callback as (fetcher: IMCDataFetcher) => void;
        break;
      case 'aborted':
        this.mOnAborted = callback as (fetcher: IMCDataFetcher, error?: Error | undefined) => void;
        break;
      case 'dataEnd':
        this.mOnDataEnd = callback as (fetcher: IMCDataFetcher) => void;;
        break;
    }
  }

  off(event: 'newDataReadable'): void;
  off(event: 'aborted'): void;
  off(event: 'dataEnd'): void;
  off(event: string): void {
    switch (event) {
      case 'newDataReadable':
        this.mOnNewDataReadable = undefined;
        break;
      case 'aborted':
        this.mOnAborted = undefined;
        break;
      case 'dataEnd':
        this.mOnDataEnd = undefined;
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
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Executing newDataReadable callback.`);
    this.mOnNewDataReadable?.(this);
  }
}