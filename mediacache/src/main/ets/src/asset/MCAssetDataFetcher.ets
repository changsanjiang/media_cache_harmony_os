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

  private mResponseReceiveCallback?: (fetcher: IMCDataFetcher, responseHeaders: IMCHttpResponseHeaders) => void | Promise<void> = undefined;
  private mDataReceiveCallback?: (fetcher: IMCDataFetcher, offset: number, data: ArrayBuffer) => void | Promise<void> = undefined;
  private mDataEndCallback?: (fetcher: IMCDataFetcher) => void = undefined;
  private mAbortedCallback?: (fetcher: IMCDataFetcher, error?: Error) => void = undefined;

  private mDataEnd = false;
  private mAborted = false;

  private mMediaDataFetcher?: IMCDataFetcher;

  constructor(clientId: number, asset: IMCAsset, request: IMCDataRequest) {
    this.mClientId = clientId;
    this.mAsset = asset;
    this.mRequest = request;

    asset.readwriteRetain();

    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Instance created for request: ${JSON.stringify(this.mRequest)}}`);
  }

  get isCompleted(): boolean {
    return this.mDataEnd || this.mAborted;
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Preparing asset reader for request: ${JSON.stringify(this.mRequest)}}`);
    try {
      const media = await this.mAsset.getMediaBy(this.mRequest.requestTarget);
      if ( this.mAborted ) {
        MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Cannot prepare as the fetcher has been aborted.`);
        return;
      }
      this.mMediaDataFetcher = new MCMediaDataFetcher(this.mClientId, media, this.mRequest);
      this.mMediaDataFetcher.on('responseReceive', (_, responseHeaders) => this.onResponseReceive(responseHeaders));
      this.mMediaDataFetcher.on('dataReceive', (_, offset, data) => this.onDataReceive(offset, data));
      this.mMediaDataFetcher.on('dataEnd', (_) => this.onDataEnd());
      this.mMediaDataFetcher.on('aborted', (_, error) => this.onError(error));
      this.mMediaDataFetcher.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Error during asset reader preparation: ${error.message}. Stack trace: ${error.stack}`);
      this.abort(error);
      throw error as Error;
    }
  }

  private async onResponseReceive(responseHeaders: IMCHttpResponseHeaders): Promise<void> {
    if ( this.mAborted ) {
      return;
    }

    try {
      if ( this.mResponseReceiveCallback ) {
        this.mResponseReceiveCallback(this, responseHeaders);
      }
    }
    catch (error) {
      this.onError(error);
      throw error as Error;
    }
  }

  private async onDataReceive(offset: number, data: ArrayBuffer): Promise<void> {
    if ( this.mAborted ) {
      return;
    }

    try {
      if ( this.mDataReceiveCallback ) {
        await this.mDataReceiveCallback(this, offset, data);
      }
    }
    catch (error) {
      this.onError(error);
      throw error as Error;
    }
  }

  private onDataEnd(): void {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    this.mDataEnd = true;

    this.mAsset.readwriteRelease();

    if ( this.mDataEndCallback ) {
      this.mDataEndCallback(this);
    }
  }

  private onError(error?: Error): void {
    if ( !this.mAborted ) {
      this.abort(error);
    }
    else {
      this.clear(error);
    }
  }

  async abort(error?: Error | undefined): Promise<void> {
    if ( this.mAborted || this.mDataEnd ) {
      return;
    }

    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Aborting fetcher${error ? ` due to error: ${error.message}` : ""}. Stack trace: ${error?.stack || 'none'}`);

    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Marking fetcher as aborted.`);

    this.mAborted = true;

    await this.clear(error);

    this.mAsset.readwriteRelease();

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private async clear(error?: Error): Promise<void> {
    const fetcher = this.mMediaDataFetcher;
    if ( fetcher ) {
      MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Clearing fetcher. Error: ${error?.message || 'none'}.`);
      this.mMediaDataFetcher = undefined;
      fetcher.off('responseReceive');
      fetcher.off('dataReceive');
      fetcher.off('dataEnd');
      fetcher.off('aborted');

      if ( !fetcher.isCompleted ) {
        try {
          MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Aborting fetcher.`);
          await fetcher.abort(error);
          MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Fetcher aborted successfully.`);
        }
        catch (abortError) {
          MCLogger.warn(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Failed to abort fetcher for request: ${this.mRequest}. Error: ${(abortError as Error)?.message || 'unknown'}`);
        }
      }
    }
  }

  on(event: "responseReceive" | "dataReceive" | "dataEnd" | "aborted", callback: Function): void {
    switch (event) {
      case 'responseReceive':
        this.mResponseReceiveCallback = callback as (fetcher: IMCDataFetcher, responseHeaders: IMCHttpResponseHeaders) => void | Promise<void>;
        break;
      case 'dataReceive':
        this.mDataReceiveCallback = callback as (fetcher: IMCDataFetcher, offset: number, data: ArrayBuffer) => void | Promise<void>;
        break;
      case 'dataEnd':
        this.mDataEndCallback = callback as (fetcher: IMCDataFetcher) => void;
        break;
      case 'aborted':
        this.mAbortedCallback = callback as (fetcher: IMCDataFetcher, error?: Error) => void;
        break;
    }
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Event listener for '${event}' registered.`);
  }

  off(event: "responseReceive" | "dataReceive" | "dataEnd" | "aborted"): void {
    switch (event) {
      case 'responseReceive':
        this.mResponseReceiveCallback = undefined;
        break;
      case 'dataReceive':
        this.mDataReceiveCallback = undefined;
        break;
      case 'dataEnd':
        this.mDataEndCallback = undefined;
        break;
      case 'aborted':
        this.mAbortedCallback = undefined;
        break;
    }
    MCLogger.debug(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Event listener for '${event}' unregistered.`);
  }
}