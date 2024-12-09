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
      return;
    }

    if ( readRange.location < content.contentOffset ) {
      this.onError(new Error(`Invalid range location: ${readRange.location} less then content offset ${content.contentOffset}.`))
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
      return;
    }

    this._mLoading = true;
    try {
      // 开始读取数据
      while (true) {
        const readableLength = Math.min(this._mReadRange.max, (this._mContent.contentOffset + this._mContent.length)) - this._mReadOffset;
        if ( readableLength == 0 ) {
          break;
        }

        const bufferSize = Math.min(4 * 1024 * 1024, readableLength);
        const buffer = new ArrayBuffer(bufferSize);
        const len = await this._mContentReader.readData(this._mReadOffset, buffer, bufferSize);
        if ( this._mAborted ) {
          throw new Error(`xxx`);
        }

        if ( len == 0 ) {
          break;
        }

        const offset = this._mReadOffset;
        this._mReadOffset += len;

        if ( this._mDataLoadCallback ) {
          await this._mDataLoadCallback(this, offset, (buffer.byteLength === len ? buffer : buffer.slice(0, len)));
          if ( this._mAborted ) {
            throw new Error(`xxx`);
          }
        }
      }
      this._mLoading = false;

      // 是否读取结束
      if (this._mReadOffset == this._mReadRange.max) {
        this._mDataEnd = true;
        if ( this._mDataEndCallback ) {
          this._mDataEndCallback(this);
        }
      }
    }
    catch (error) {
      this._mLoading = false;
      this.onError(error);
      throw error as Error;
    }
  }

  protected onError(error?: Error) {
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
      return;
    }

    this._mAborted = true;
    try { await this.clear(); } catch (_) { }

    if ( this._mAbortedCallback ) {
      this._mAbortedCallback(this, error);
    }
  }

  private async clear(): Promise<void> {
    if ( this._mContent ) {
      this._mContent.off('dataWritten');
      this._mContent = undefined;
      try { await this._mContentReader?.close(); } catch (_) { }
      this._mContentReader = undefined;
    }

    await this.onClear();
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