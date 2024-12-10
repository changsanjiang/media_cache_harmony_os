import { IMCMediaContent, IMCMediaContentReader } from "../defines/IMCMediaContent";
import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { MCRange } from "../utils/MCRange";

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
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Loader aborted before preparation complete.`);
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
    this._mContent.on('dataWritten', (_) => this.onLoadData());
    setTimeout(() => this.onLoadData());
  }

  private async onLoadData(): Promise<void> {
    if ( this._mAborted || this._mDataEnd || this._mLoading || !this._mContent || !this._mReadRange || !this._mContentReader ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Load data skipped. Aborted: ${this._mAborted}, DataEnd: ${this._mDataEnd}, Loading: ${this._mLoading}`);
      return;
    }

    this._mLoading = true;
    try {
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Starting data load at offset ${this._mReadOffset}.`);

      // 开始读取数据
      while (true) {
        const readableLength = Math.min(this._mReadRange.max, (this._mContent.contentOffset + this._mContent.length)) - this._mReadOffset;
        if ( readableLength == 0 ) {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `No more data to read. waiting for next callback.`);
          break;
        }

        const bufferSize = Math.min(4 * 1024 * 1024, readableLength);
        const buffer = new ArrayBuffer(bufferSize);
        const len = await this._mContentReader.readData(this._mReadOffset, buffer, bufferSize);
        if ( this._mAborted ) {
          throw new Error(`The contet loader has been aborted.`);
        }

        if ( len == 0 ) {
          MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `No data was read. waiting for next callback.`);
          break;
        }

        const offset = this._mReadOffset;
        this._mReadOffset += len;

        MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Data loaded at offset ${offset}, length: ${len}.`);

        if ( this._mDataLoadCallback ) {
          await this._mDataLoadCallback(this, offset, (buffer.byteLength === len ? buffer : buffer.slice(0, len)));
          if ( this._mAborted ) {
            throw new Error(`The contet loader has been aborted.`);
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
          this._mDataEndCallback(this);
        }
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error during data loading: ${error}, stack: ${error.stack}`);

      this._mLoading = false;
      this.onError(error);
      throw error as Error;
    }
  }

  protected onError(error?: Error) {
    MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error occurred: ${error?.message || "Unknown error"}.`);

    if ( !this._mAborted ) {
      this.abort(error);
    }
    else {
      this.clear();
    }
  }

  protected async onClear(): Promise<void> { }

  async abort(error?: Error): Promise<void> {
    if ( this._mAborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Abort called, but loader is already aborted.`);
      return;
    }

    this._mAborted = true;
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Aborting loader.`);

    await this.clear();

    if ( this._mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing aborted callback with error: ${error?.message || 'None'}.`);

      this._mAbortedCallback(this, error);
    }
  }

  private async clear(): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Clearing resources. Content: ${this._mContent}, ContentReader: ${this._mContentReader}.`);

    if ( this._mContent ) {
      this._mContent.off('dataWritten');
      this._mContent = undefined;
      try {
        await this._mContentReader?.close();
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error closing content reader: ${error}`);
      }
      this._mContentReader = undefined;
    }

    try { await this.onClear(); } catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error executing onClear: ${error}`);
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