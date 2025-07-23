import { IMCMediaContent, IMCMediaContentReader } from '../defines/IMCMediaContent';
import { IMCMediaContentLoader } from '../defines/IMCMediaContentLoader';
import { MCLogModule } from '../defines/MCLogModule';
import MCLogger from '../utils/MCLogger';
import { MCRange } from '../utils/MCRange';
import { MCMediaContentLoaderState } from '../defines/MCMediaContentLoaderState';

export class MCMediaContentLoader implements IMCMediaContentLoader {
  private _mState = MCMediaContentLoaderState.Unknown;
  private _mReadRange = MCRange.zero;
  private _mReadOffset = 0;
  private _mError?: Error = undefined;
  private _mOnStateChange?: (loader: IMCMediaContentLoader, state: MCMediaContentLoaderState) => void = undefined;
  private _mOnNewDataReadable?: (loader: IMCMediaContentLoader) => void = undefined;

  private _mContent?: IMCMediaContent = undefined;
  private _mContentReader?: IMCMediaContentReader = undefined;
  private _mReadCount: number = 0; // read 操作调用批次

  private mClientId: number;
  private mLoaderId: number;

  constructor(clientId: number, loaderId: number) {
    this.mClientId = clientId;
    this.mLoaderId = loaderId;
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${clientId}_${loaderId}] Instance created.`);
  }

  get state(): MCMediaContentLoaderState {
    return this._mState;
  }

  get range(): MCRange {
    return this._mReadRange;
  }

  get offset(): number {
    return this._mReadOffset;
  }

  get readableLength(): number {
    if ( this.isReady ) {
      const content = this._mContent;
      const readRange = this._mReadRange;
      const readOffset = this._mReadOffset;
      if ( content ) {
        const contentStart = content.contentOffset;
        const contentEnd = contentStart + content.length;

        const readEnd = readRange.max;

        // 当前 offset 不能小于 content 起始位置或超过读取范围终点
        if ( readOffset < contentStart || readOffset >= readEnd ) {
          return 0;
        }

        // 可读范围 = 当前 offset 到两者共同的结束位置（取较小值）
        const readableEnd = Math.min(contentEnd, readEnd);
        return readableEnd - readOffset;
      }
    }
    return 0;
  }

  get error(): Error | undefined {
    return this._mError;
  }

  prepare(): Promise<void> {
    throw new Error("Method 'prepare()' must be implemented in subclass.");
  }

  async read(capacity: number): Promise<ArrayBuffer | undefined> {
    if ( !this.isReady || this._mContentReader == undefined ) {
      return undefined;
    }

    const readableLength = this.readableLength;
    if ( readableLength == 0 ) {
      return undefined;
    }

    const reader = this._mContentReader;
    if ( reader === undefined ) {
      return undefined;
    }

    const readIndex = this._mReadCount++;
    try {
      const offset = this._mReadOffset;
      const bufferSize = Math.min(capacity, readableLength);
      const buffer = new ArrayBuffer(bufferSize);

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}_${this.loaderId}] [#${readIndex}] Attempting to read ${bufferSize} bytes at offset ${offset}`);

      const len = await reader.readData(offset, buffer, bufferSize);

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}_${this.loaderId}] [#${readIndex}] Read ${len} bytes`);

      if ( this.isAborted ) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] [#${readIndex}] Aborted after read attempt. Ignoring result`);
        return undefined;
      }

      if ( len == 0 ) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] [#${readIndex}] No data read in current attempt`);
        return undefined;
      }

      this._mReadOffset += len;

      if ( this._mReadOffset == this._mReadRange.max ) {
        this.onReachedEnd();
      }
      return buffer;
    }
    catch (e) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] [#${readIndex}] Error during data load: ${e.message}, Stack trace: ${e.stack}`);
      this.onError(e as Error);
    }
    return undefined;
  }

  seek(offset: number): boolean {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}_${this.loaderId}] Attempting to seek to offset ${offset}`);

    const content = this._mContent;
    if (content && this.isReady) {
      const readRange = this._mReadRange;
      const readStart = readRange.location;
      const readEnd = readRange.max;

      if (offset < readStart || offset > readEnd) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}_${this.loaderId}] Seek offset ${offset} out of range [${readStart}, ${readEnd}]`);
        return false;
      }

      this._mReadOffset = offset;

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}] Seek successful to offset ${offset}`);

      if (offset === readEnd) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}_${this.loaderId}] Seek reached end of read range at ${offset}`);
        this.onReachedEnd();
      }
      return true;
    }

    MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}_${this.loaderId}] Seek failed: content is not ready`);
    return false;
  }

  abort(error?: Error | undefined): void {
    if ( this._mState == MCMediaContentLoaderState.Aborted ) {
      return;
    }

    this._mState = MCMediaContentLoaderState.Aborted;
    this._mError = error ?? new Error("Load task was aborted");
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Loader aborted: ${this._mError?.message}`);
    this.clear();
    this.notifyStateChange();
  }

  on(event: 'stateChange', callback: (loader: IMCMediaContentLoader, state: MCMediaContentLoaderState) => void): void;
  on(event: 'newDataReadable', callback: (loader: IMCMediaContentLoader) => void): void;
  on(event: string, callback: Object): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}] ${event} callback registered`);

    switch (event) {
      case "stateChange":
        this._mOnStateChange = callback as (loader: IMCMediaContentLoader, state: MCMediaContentLoaderState) => void;
        break;
      case "newDataReadable":
        this._mOnNewDataReadable = callback as (loader: IMCMediaContentLoader) => void;
        break;
    }
  }

  off(event: 'stateChange'): void;
  off(event: 'newDataReadable'): void;
  off(event: string): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.mClientId}] ${event} callback removed`);

    switch (event) {
      case "stateChange":
        this._mOnStateChange = undefined;
        break;
      case "newDataReadable":
        this._mOnNewDataReadable = undefined;
        break;
    }
  }

  get isAborted(): boolean {
    return this._mState == MCMediaContentLoaderState.Aborted;
  }

  get isReady(): boolean {
    return this._mState == MCMediaContentLoaderState.Ready;
  }

  get clientId(): number {
    return this.mClientId;
  }
  
  get loaderId(): number {
    return this.mLoaderId;
  }

  private clear(): void {
    const content = this._mContent;
    const reader = this._mContentReader;

    if ( content ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Clearing resources. Content: ${this._mContent}, ContentReader: ${this._mContentReader}`);

      this._mContentReader = undefined;
      this._mContent = undefined;

      content.off('dataWritten');
      reader?.close().then(() => {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Content reader successfully closed`);
      }).catch((error: Error) => {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Error closing content reader: ${error}. Stack trace: ${error.stack}`);
      });
    }

    this.onClear();
  }

  protected onPrepared(content: IMCMediaContent, readRange: MCRange): void {
    if (this._mState == MCMediaContentLoaderState.Aborted ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Loader already aborted before content preparation. Skipping bind`);
      return;
    }

    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Loader prepared with range ${JSON.stringify(readRange)}`);

    if ( readRange.location < content.contentOffset ) {
      this.onError(new Error(`Invalid range location: ${readRange.location} is less than content offset ${content.contentOffset}.`))
      return;
    }

    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Content accepted. Binding content reader and listeners`);

    this._mContent = content;
    this._mContentReader = content.createReader();
    this._mContent.on('dataWritten', (_) => this.notifyNewDataReadable());
    this._mReadRange = readRange;
    this._mReadOffset = readRange.location;
    this._mState = MCMediaContentLoaderState.Ready;

    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Finished prepare. Loader marked as Ready`);
    this.notifyStateChange();

    if ( this.readableLength > 0 ) {
      this.notifyNewDataReadable();
    }
  }

  protected onError(error?: Error): void {
    if ( this._mState === MCMediaContentLoaderState.Aborted ) {
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] onError called but loader is already aborted`);
      return;
    }

    MCLogger.error(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Loader entering aborted state due to error: ${error?.message}`);
    this.abort(error ?? new Error("Unknown error during loader operation"));
  }

  protected async onClear(): Promise<void> { }

  private onReachedEnd(): void {
    this._mState = MCMediaContentLoaderState.Ended;
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] Reached end of read range at offset ${this._mReadOffset}. Loader marked as Ended`);
    this.clear(); // 读取完毕后清理资源;
    this.notifyStateChange();
  }

  private notifyStateChange() {
    setTimeout(() => {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] notifyStateChange() triggered. New state: ${MCMediaContentLoaderState[this._mState]}, Callback: ${this._mOnStateChange}`);
      this._mOnStateChange?.(this, this._mState);
    });
  }

  private notifyNewDataReadable(): void {
    setTimeout(() => {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `[clientId: ${this.clientId}_${this.loaderId}] notifyNewDataReadable() triggered. Offset: ${this._mReadOffset}, ReadableLength: ${this.readableLength}, Callback: ${this._mOnNewDataReadable}`);
      this._mOnNewDataReadable?.(this);
    })
  }
}