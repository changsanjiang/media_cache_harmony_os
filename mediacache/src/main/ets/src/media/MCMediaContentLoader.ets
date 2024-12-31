import { IMCMediaContent, IMCMediaContentReader } from "../defines/IMCMediaContent";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";
import { BusinessError } from "@kit.BasicServicesKit";
import MCConfigs from "../utils/MCConfigs";

export class MCMediaContentLoader implements IMCMediaContentLoader {
  private _mDataLoadCallback?: (loader: IMCMediaContentLoader, offset: number, data: ArrayBuffer) => void | Promise<void> = undefined;
  private _mDataEndCallback?: (loader: IMCMediaContentLoader) => void = undefined;
  private _mAbortedCallback?: (loader: IMCMediaContentLoader, error?: Error | undefined) => void;
  private _mDataEnd = false;
  private _mAborted = false;
  private _mContent?: IMCMediaContent = undefined;
  private _mContentReader?: IMCMediaContentReader = undefined;
  private _mLoading = false;
  private _mReadRange?: MCRange = undefined;
  private _mReadOffset: number = 0;

  constructor() {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Instance created.`);
  }

  get isAborted(): boolean {
    return this._mAborted;
  }

  prepare(): Promise<void> {
    throw new Error("Method 'prepare()' must be implemented in subclass.");
  }

  protected onPrepared(content: IMCMediaContent, readRange: MCRange): void {
    if (this._mAborted) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Loader aborted before preparation was completed.`);
      return;
    }

    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Loader prepared with range ${JSON.stringify(readRange)}.`);

    if ( readRange.location < content.contentOffset ) {
      this.onError(new Error(`Invalid range location: ${readRange.location} is less than content offset ${content.contentOffset}.`))
      return;
    }

    this._mContent = content;
    this._mContentReader = content.createReader();
    this._mReadRange = readRange;
    this._mReadOffset = readRange.location;
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Reader and range initialized. Waiting for data load events.`);

    this._mContent.on('dataWritten', (_) => {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Data written event received. Triggering data load.`);
      this.onLoadData();
    });
    setTimeout(() => this.onLoadData());
  }

  private async onLoadData(): Promise<void> {
    if ( this._mAborted || this._mDataEnd || this._mLoading || !this._mContent || !this._mReadRange || !this._mContentReader ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Skipped data load. Aborted: ${this._mAborted}, DataEnd: ${this._mDataEnd}, Loading: ${this._mLoading}`);
      return;
    }

    this._mLoading = true;
    try {
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Starting data load at offset ${this._mReadOffset}.`);

      // 开始读取数据
      while (true) {
        const readableLength = Math.min(this._mReadRange.max, (this._mContent.contentOffset + this._mContent.length)) - this._mReadOffset;
        if ( readableLength == 0 ) {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `No more data available to read.`);
          break;
        }

        const bufferSize = Math.min(MCConfigs.socketDataBufferSize, readableLength);
        const buffer = new ArrayBuffer(bufferSize);
        const len = await this._mContentReader.readData(this._mReadOffset, buffer, bufferSize);
        if ( this._mAborted ) {
          throw new Error(`Loader aborted after reading data.`);
        }

        if ( len == 0 ) {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `No data read in current attempt. Waiting for further events.`);
          break;
        }

        const offset = this._mReadOffset;
        this._mReadOffset += len;

        MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Loaded data block at offset ${offset}, size: ${len} bytes.`);

        if ( this._mDataLoadCallback ) {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Invoking data load callback for offset ${offset}, size: ${len}.`);
          await this._mDataLoadCallback(this, offset, (buffer.byteLength === len ? buffer : buffer.slice(0, len)));
          if ( this._mAborted ) {
            throw new Error(`Loader aborted after invoking data load callback.`);
          }
        }
      }
      this._mLoading = false;

      // 是否读取结束
      if (this._mReadOffset == this._mReadRange.max) {
        this._mDataEnd = true;
        await this.clear();
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Data loading complete.`);
        if ( this._mDataEndCallback ) {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing data end callback.`);
          this._mDataEndCallback(this);
        }
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error during data load: ${error.message}, Stack trace: ${error.stack}`);

      this._mLoading = false;
      this.onError(error);
      throw error as Error;
    }
  }

  protected onError(error?: Error) {
    MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Handling error: ${(error as Error).message ?? ((error as BusinessError).code)}, Stack trace: ${error?.stack}`);

    if (!this._mAborted) {
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Aborting due to error.`);
      this.abort(error);
    }
    else {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Error handled after abort. Clearing resources.`);
      this.clear();
    }
  }

  protected async onClear(): Promise<void> { }

  async abort(error?: Error): Promise<void> {
    if ( this._mAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Abort was called, but the loader is already aborted.`);
      return;
    }

    this._mAborted = true;
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Aborting loader. Error provided: ${error?.message || 'none'}, Stack trace: ${error?.stack}}.`);

    await this.clear();

    if ( this._mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing aborted callback with error: ${error?.message || 'none'}`);

      this._mAbortedCallback(this, error);
    }
  }

  private async clear(): Promise<void> {
    const content = this._mContent;
    const reader = this._mContentReader;

    if ( content ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Clearing resources. Content: ${this._mContent}, ContentReader: ${this._mContentReader}.`);

      this._mContentReader = undefined;
      this._mContent = undefined;

      content.off('dataWritten');
      try {
        await reader?.close();
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Content reader successfully closed.`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error closing content reader: ${error}. Stack trace: ${error.stack}`);
      }
    }

    try {
      await this.onClear();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error during onClear execution: ${error.message}. Stack trace: ${error.stack}`);
    }
  }

  on(event: "dataLoad" | "dataEnd" | "aborted", callback: Function): void {
    switch (event) {
      case "dataLoad":
        this._mDataLoadCallback = callback as (loader: IMCMediaContentLoader, offset: number, data: ArrayBuffer) => void | Promise<void>;
        break;
      case "dataEnd":
        this._mDataEndCallback = callback as (loader: IMCMediaContentLoader) => void;
        break;
      case "aborted":
        this._mAbortedCallback = callback as (loader: IMCMediaContentLoader, error?: Error | undefined) => void;
        break;
    }
  }

  off(event: "dataLoad" | "dataEnd" | "aborted"): void {
    switch (event) {
      case "dataLoad":
        this._mDataLoadCallback = undefined;
        break;
      case "dataEnd":
        this._mDataEndCallback = undefined;
        break;
      case "aborted":
        this._mAbortedCallback = undefined;
        break;
    }
  }
}