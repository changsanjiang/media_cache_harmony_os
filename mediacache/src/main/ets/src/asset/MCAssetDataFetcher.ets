import { IMCAsset } from "../defines/IMCAsset";
import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { MCDataDecryptHandler } from "../defines/MCDataDecryptHandler";
import { MCLogModule } from "../defines/MCLogModule";
import { MCMediaDataFetcher } from "../media/MCMediaDataFetcher";
import MCLogger from "../utils/MCLogger";

export class MCAssetDataFetcher implements IMCDataFetcher {
  private mClientId: number;
  private mRequest: IMCDataRequest;
  private mAsset: IMCAsset;
  private mDecrypt?: MCDataDecryptHandler;

  private mResponseReceiveCallback?: (fetcher: IMCDataFetcher, responseHeaders: string) => void | Promise<void> = undefined;
  private mDataReceiveCallback?: (fetcher: IMCDataFetcher, offset: number, data: ArrayBuffer) => void | Promise<void> = undefined;
  private mDataEndCallback?: (fetcher: IMCDataFetcher) => void = undefined;
  private mAbortedCallback?: (fetcher: IMCDataFetcher, error?: Error) => void = undefined;

  private mDataEnd = false;
  private mAborted = false;

  private mMediaDataFetcher?: IMCDataFetcher;

  constructor(clientId: number, asset: IMCAsset, request: IMCDataRequest, decrypt?: MCDataDecryptHandler) {
    this.mClientId = clientId;
    this.mAsset = asset;
    this.mRequest = request;
    this.mDecrypt = decrypt;

    asset.readwriteRetain();

    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Instance created  for request: ${JSON.stringify(this.mRequest)}}`);
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Preparing asset reader for request: ${JSON.stringify(this.mRequest)}}`);
    try {
      const media = await this.mAsset.getMediaBy(this.mRequest.requestTarget);
      if ( this.mAborted ) {
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
      MCLogger.error(MCLogModule.MCAssetDataFetcher, () => `[clientId: ${this.mClientId}] Error during asset reader preparation: ${error.message}`);
      this.abort(error);
      throw error as Error;
    }
  }

  private async onResponseReceive(responseHeaders: string): Promise<void> {
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

    if ( this.mDecrypt ) {
      await this.mDecrypt(this.mRequest, offset, data);
    }

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

    this.mAborted = true;

    await this.clear(error);

    this.mAsset.readwriteRelease();

    if ( this.mAbortedCallback ) {
      this.mAbortedCallback(this, error);
    }
  }

  private async clear(error?: Error): Promise<void> {
    if ( this.mMediaDataFetcher ) {
      this.mMediaDataFetcher.off('responseReceive');
      this.mMediaDataFetcher.off('dataReceive');
      this.mMediaDataFetcher.off('dataEnd');
      this.mMediaDataFetcher.off('aborted');
      try { await this.mMediaDataFetcher.abort(error); } catch (_) { }
      this.mMediaDataFetcher = undefined;
    }
  }

  on(event: "responseReceive" | "dataReceive" | "dataEnd" | "aborted", callback: Function): void {
    switch (event) {
      case 'responseReceive':
        this.mResponseReceiveCallback = callback as (fetcher: IMCDataFetcher, responseHeaders: string) => void | Promise<void>;
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
  }
}