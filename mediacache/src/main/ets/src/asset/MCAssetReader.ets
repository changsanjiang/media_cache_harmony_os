import { IMCAsset } from "../defines/IMCAsset";
import { IMCDataReader } from "../defines/IMCDataReader";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { MCDataDecryptHandler } from "../defines/MCDataDecryptHandler";
import { MCLogModule } from "../defines/MCLogModule";
import { MCMediaDataReader } from "../media/MCMediaDataReader";
import MCLogger from "../utils/MCLogger";
import MCAssetManager from "./MCAssetManager";

export class MCAssetReader implements IMCDataReader {
  private mClientId: number;
  private mProxyRequest: IMCDataRequest;
  private mAsset?: IMCAsset;
  private mDecrypt?: MCDataDecryptHandler;
  private mMediaReader?: IMCDataReader;
  private mDone = false;
  private mAborted = false;
  private mResponseReadyCallback?: (reader: IMCDataReader, responseHeaders: string) => void = undefined;
  private mNewDataReadableCallback?: (reader: IMCDataReader) => void = undefined;
  private mAbortedCallback?: (reader: IMCDataReader, error?: Error | undefined) => void = undefined;
  private mDoneCallback?: (reader: IMCDataReader) => void = undefined;

  constructor(clientId: number, proxyRequest: IMCDataRequest, decrypt?: MCDataDecryptHandler) {
    this.mClientId = clientId;
    this.mProxyRequest = proxyRequest;
    this.mDecrypt = decrypt;

    MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Instance created  for request: ${JSON.stringify(this.mProxyRequest)}}`);
  }

  get responseHeaders(): string | undefined {
    return this.mMediaReader?.responseHeaders;
  }
  get isDone(): boolean {
    return this.mDone;
  }
  get isAborted(): boolean {
    return this.mAborted;
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Preparing asset reader for request: ${JSON.stringify(this.mProxyRequest)}}`);

    try {
      this.mAsset = await MCAssetManager.getAssetBy(this.mProxyRequest.requestTarget);
      const media = await this.mAsset.getMediaBy(this.mProxyRequest.requestTarget);
      this.mMediaReader = new MCMediaDataReader(media, this.mClientId, this.mProxyRequest, this.mDecrypt);
      this.mMediaReader.on("responseReady", (_, responseHeaders) => this.responseReady(responseHeaders));
      this.mMediaReader.on("newDataReadable", () => this.newDataReadable());
      this.mMediaReader.on("aborted", (_, error) => this.abort(error));
      this.mMediaReader.on("done", () => this.done());
      this.mMediaReader.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Error during asset reader preparation: ${error.message}`);
      this.abort(error);
      throw error as Error;
    }
  }

  async readData(): Promise<ArrayBuffer | undefined> {
    try {
      MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Starting readData.`);

      if (this.mDone || this.mAborted || !this.mMediaReader) {
        MCLogger.warn(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Cannot read data. Status - Done: ${this.mDone}, Aborted: ${this.mAborted}, MediaReader: ${this.mMediaReader}.`);
        return undefined;
      }

      const buffer = await this.mMediaReader.readData();
      if ( buffer ) {
        MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Read ${buffer.byteLength} bytes of data.`);
      }
      else {
        MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] No data was read, the buffer is empty.`);
      }
      return buffer;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Error during data read: ${error.message}, stack: ${error.stack}`);
      this.abort(error);
      throw error as Error;
    }
  }

  async seekToEndOfReadableRange(): Promise<number> {
    MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Starting seekToEndOfReadableRange.`);

    if (this.mDone || this.mAborted || !this.mMediaReader) {
      MCLogger.warn(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Seek operation aborted. Status - Done: ${this.mDone}, Aborted: ${this.mAborted}, MediaReader: ${this.mMediaReader}.`);
      return 0;
    }

    try {
      const len = await this.mMediaReader.seekToEndOfReadableRange();
      if (len > 0) {
        MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Seeked ${len} bytes to the end of the readable range.`);
      }
      else {
        MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] No data skipped during seek operation. Likely already at the end of the readable range.`);
      }
      return len;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Error during seek operation: ${error.message}`);
      this.abort(error);
      throw error as Error;
    }
  }

  private responseReady(responseHeaders: string): void {
    if ( !this.mAborted && !this.mDone && this.mResponseReadyCallback ) {
      MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Executing responseReady callback with responseHeaders: \n${responseHeaders}`);
      this.mResponseReadyCallback(this, responseHeaders);
    }
  }

  private newDataReadable(): void {
    if ( !this.mAborted && !this.mDone && this.mNewDataReadableCallback ) {
      MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Executing newDataReadable callback.`);
      this.mNewDataReadableCallback(this);
    }
  }

  private done(): void {
    if ( this.mAborted || this.mDone ) {
      return;
    }

    this.mDone = true;
    this.clear();

    if (this.mDoneCallback) {
      MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Execution of done callback.`);
      this.mDoneCallback(this);
    }
  }

  async abort(error?: Error | undefined): Promise<void> {
    if ( this.mAborted || this.mDone ) {
      return;
    }

    MCLogger.warn(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Aborting MCAssetReader${error ? ` due to error: ${error.message}` : ""}.`);

    this.mAborted = true;
    MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Reader marked as aborted.`);

    this.mMediaReader?.abort(error);

    this.clear();

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private clear() {
    if ( this.mMediaReader ) {
      this.mMediaReader.off("responseReady");
      this.mMediaReader.off("newDataReadable");
      this.mMediaReader.off("aborted");
      this.mMediaReader.off("done");
      this.mMediaReader = undefined;
    }

    this.mAsset?.readwriteRelease();
    this.mAsset = undefined;

    MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Resources released and cleared.`);
  }

  on(event: 'responseReady' | 'newDataReadable' | 'aborted' | 'done', callback: Object): void {
    MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Registering callback for event '${event}'.`);

    switch (event) {
      case "responseReady":
        this.mResponseReadyCallback = callback as (reader: IMCDataReader, responseHeaders: string) => void;
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
  }

  off(event: 'responseReady' | 'newDataReadable' | 'aborted' | 'done'): void {
    MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Removing callback for event '${event}'.`);

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
  }
}