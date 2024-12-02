import { IMCAsset } from "../defines/IMCAsset";
import { IMCDataReader } from "../defines/IMCDataReader";
import { IMCDataRequest } from "../defines/IMCDataRequest";
import { IMCMedia } from "../defines/IMCMedia";
import { MCDataDecryptHandler } from "../defines/MCDataDecryptHandler";
import { ArkTSUtils } from "@kit.ArkTS";
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
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
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
  }

  get readableLength(): Promise<number> {
    return this.mLock.lockAsync(() => this.mMediaReader?.readableLength ?? 0);
  }
  get responseHeaders(): Promise<string | undefined> {
    return this.mLock.lockAsync(() => this.mMediaReader?.responseHeaders);
  }
  get isDone(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mDone);
  }
  get isAborted(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAborted);
  }

  async prepare(): Promise<void> {
    return this.mLock.lockAsync(async () => {
      try {
        MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Starting preparation.`);

        if (this.mDone || this.mAborted) {
          MCLogger.warn(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Attempted to prepare, but the reader is already done or aborted.`);
          return;
        }
        this.mAsset = await MCAssetManager.getAssetBy(this.mProxyRequest.requestTarget);
        const media = await this.mAsset.getMediaBy(this.mProxyRequest.requestTarget);
        this.mMediaReader = new MCMediaDataReader(media, this.mClientId, this.mProxyRequest, this.mDecrypt);
        this.mMediaReader.on("responseReady", (_, responseHeaders) => {
          this.mLock.lockAsync(() => !this.mDone && !this.mAborted ? this.mResponseReadyCallback : undefined).then((callback) => {
            if ( callback ) {
              MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Executing responseReady callback with responseHeaders: ${responseHeaders}.`);
              callback(this, responseHeaders);
            }
          });
        });
        this.mMediaReader.on("newDataReadable", () => {
          this.mLock.lockAsync(() => !this.mDone && !this.mAborted ? this.mNewDataReadableCallback : undefined).then((callback) => {
            if ( callback ) {
              MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Executing newDataReadable callback.`);
              callback(this);
            }
          });
        });
        this.mMediaReader.on("aborted", (_, error) => this.abort(error));
        this.mMediaReader.on("done", () => {
          this.mLock.lockAsync(() => {
            if ( this.mAborted ) {
              return;
            }
            this.mDone = true;
            this.clear();
            Promise.resolve(this.mDoneCallback).then((callback) => {
              if (callback) {
                MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Execution of done callback.`);
                callback(this);
              }
            });
          });
        });
        MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Preparing media reader.`);
        return this.mMediaReader.prepare();
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Error during media reader preparation: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  readData(buffer: ArrayBuffer): Promise<number> {
    return this.mLock.lockAsync(() => {
      try {
        MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Reading data into buffer of size: ${buffer.byteLength}.`);

        const len = this.mMediaReader?.readData(buffer) ?? 0;
        MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Read ${len} bytes of data.`);
        return len;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Error during data read: ${error.message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  seekToEndOfReadableRange(): Promise<number> {
    return this.mLock.lockAsync(() => {
      try {
        MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Seeking to the end of the readable range.`);

        const len = this.mMediaReader?.seekToEndOfReadableRange() ?? 0;
        MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Seeked to the end, result: ${len} bytes.`);
        return len;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Error during seek operation: ${error.message}`);
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
    });
  }

  off(event: 'responseReady' | 'newDataReadable' | 'aborted' | 'done'): Promise<void> {
    return this.mLock.lockAsync(() => {
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
    });
  }

  private abortUnsafe(error?: Error): void {
    if ( this.mAborted ) {
      return;
    }

    MCLogger.warn(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Aborting MCAssetReader${error ? ` due to error: ${error.message}` : ""}.`);

    this.mAborted = true;
    MCLogger.info(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Reader marked as aborted.`);

    this.mMediaReader?.abort(error);

    this.clear();

    Promise.resolve(this.mAbortedCallback).then((callback) => {
      if ( callback ) {
        MCLogger.debug(MCLogModule.MCAssetReader, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
        callback(this, error);
      }
    });
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
}