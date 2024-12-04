import { IMCMediaContentLoader, MCMediaContentDecryptHandler } from "../defines/IMCMediaContentLoader";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCRange } from "../utils/MCRange";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { MCSerialQueue } from "../../../../../Index";

export class MCMediaContentLoader implements IMCMediaContentLoader {
  private mNewDataReadableCallback?: (loader: IMCMediaContentLoader) => void = undefined;
  private mAbortedCallback?: (loader: IMCMediaContentLoader, error?: Error) => void = undefined;
  private mDoneCallback?: (loader: IMCMediaContentLoader) => void = undefined;
  private mReadOffset = 0;
  protected mDone = false;
  protected mAborted = false;
  private mContent?: IMCMediaContent = undefined;
  private mReadRange?: MCRange = undefined;
  private mSerialQueue = new MCSerialQueue();

  constructor() {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Instance created.`);
  }

  get isDone(): boolean {
    return this.mDone;
  }

  get isAborted(): boolean {
    return this.mAborted;
  }

  get range(): MCRange | undefined {
    return this.mReadRange;
  }

  get offset(): number {
    return this.mReadOffset;
  }

  async prepare(): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Starting preparation.');
    if (this.mAborted) {
      MCLogger.warn(MCLogModule.MCMediaDataReader, () => `Cannot prepare as the loader has been aborted.`);
      return;
    }

    try {
      await this.onPrepare();
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Loader preparation complete.');
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error during preparation: ${(error as Error).message}, stack: ${error.stack}}`);
      this.abort(error);
      throw error as Error;
    }
  }

  protected onPrepare(): Promise<void> {
    throw new Error("Method 'onPrepare()' must be implemented in subclass. Ensure your subclass overrides this method with necessary preparation logic.");
  }

  /// 实现类在准备好 content 之后, 调用该方法通知抽象类;
  ///
  /// 实现类通知抽象类已准备好 content;
  /// 调用前请对 content 做一次 readwriteRetain 操作, 防止被提前 release; 之后不需要外部调用 release, 抽象类会在读取操作结束后进行清理操作;
  protected async contentReady(content: IMCMediaContent, range: MCRange): Promise<void> {
    try {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Content ready event received. Checking conditions.`);

      if (this.mAborted) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Content ready event ignored due to aborted loader.');
        return;
      }

      if ( range.location < content.contentOffset ) {
        throw new Error(`Invalid range location: ${range.location} less then content offset ${content.contentOffset}.`);
      }

      this.mContent = content;
      this.mReadRange = range;
      this.mReadOffset = range.location;
      this.mContent.on('dataWritten', (_: IMCMediaContent) => this.newDataReadable()); // 实现类通知抽象类可加载数据了;

      const readableLength = Math.min(this.mReadRange.max, (this.mContent.contentOffset + this.mContent.length)) - this.mReadOffset;

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Read offset set to ${this.mReadOffset}.`);
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Content is ready. Range: ${JSON.stringify(range)}, Content offset: ${content.contentOffset}, Readable length: ${readableLength}.`);

      if ( readableLength > 0 ) {
        this.newDataReadable();
      }

      if ( range.length === 0 ) {
        this.done();
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error in contentReady: ${(error as Error).message}, stack: ${error.stack}`);
      this.abort(error);
      throw error as Error;
    }
  }

  // 有新的数据写入了， 通知外部可以读取数据了;
  private newDataReadable(): void {
    setTimeout(() => {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `New data readable.`);

      if ( !this.mDone && !this.mAborted && this.mNewDataReadableCallback ) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing dataLoaded callback.`);
        this.mNewDataReadableCallback(this);
      }
    });
  }

  async readData(decrypt?: MCMediaContentDecryptHandler): Promise<ArrayBuffer | undefined> {
    return this.mSerialQueue.enqueue(async () => {
      try {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Attempting to read data.`);

        if (this.mAborted) {
          MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Read aborted due to loader being aborted.');
          return undefined;
        }

        if (this.mDone) {
          MCLogger.info(MCLogModule.MCMediaContentLoader, () => 'Read operation ignored as the loader is already done.');
          return undefined;
        }

        if (!this.mContent || !this.mReadRange) {
          MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'No content available for reading.');
          return undefined;
        }

        const readableLength = Math.min(this.mReadRange.max, (this.mContent.contentOffset + this.mContent.length)) - this.mReadOffset;
        if ( readableLength == 0 ) {
          MCLogger.info(MCLogModule.MCMediaContentLoader, () => `No data available to read (readable length is 0).`);
          return undefined;
        }

        const bufferSize = Math.min(4 * 1024 * 1024, readableLength);
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Calculated buffer size: ${bufferSize}.`);
        const buffer = new ArrayBuffer(bufferSize);

        // 执行读取操作
        const len = await this.mContent.readData(this.mReadOffset, buffer, bufferSize);
        if ( len > 0 ) {
          MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Successfully read ${len} bytes at offset ${this.mReadOffset}.`);

          if ( decrypt ) {
            const decryptedLength = await decrypt(this.mReadOffset, buffer, len);
            // 解密后的数据长度不能发生改变;
            if (decryptedLength !== len) {
              throw new Error(`Decryption failed: expected ${len} bytes, but got ${decryptedLength} bytes.`);
            }
            MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Successfully decrypted ${decryptedLength} bytes.`);
          }
        }
        else {
          MCLogger.info(MCLogModule.MCMediaContentLoader, () => `No data read (buffer length is zero).`);
        }

        this.increaseReadOffset(len);
        return len > 0 ? (buffer.byteLength === len ? buffer : buffer.slice(0, len)) : undefined;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error reading data: ${(error as Error).message}`);
        this.abort(error);
        throw error as Error;
      }
    });
  }

  async seekToEndOfReadableRange(): Promise<number> {
    return this.mSerialQueue.enqueue(() => {
      try {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Attempting to seek to the end of the readable range.`);
        if (!this.mContent || !this.mReadRange) {
          MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'No content available for reading.');
          return 0;
        }

        const readableLength = Math.min(this.mReadRange.max, (this.mContent.contentOffset + this.mContent.length)) - this.mReadOffset;
        if ( readableLength > 0 ) {
          MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Seeked to the end of readable range. Total readable length: ${readableLength}.`);
          this.increaseReadOffset(readableLength); // 直接增加偏移量即可;
        }
        else {
          MCLogger.info(MCLogModule.MCMediaContentLoader, () => `No data can be skipped (already at the end).`);
        }
        return readableLength;
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error seeking to the end of readable range: ${(error as Error).message}, stack: ${error.stack}`);
        this.abort(error);
        throw error as Error;
      }
    });
  }

  private increaseReadOffset(length: number) {
    if ( length > 0 ) {
      this.mReadOffset += length;
      const done = this.mReadOffset === this.mReadRange!.max;

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Offset increased by ${length}, current offset: ${this.mReadOffset}. Range max: ${this.mReadRange!.max}.`);

      if ( done ) {
        this.done();
      }
    }
  }

  private async done(): Promise<void> {
    if ( this.mAborted || this.mDone ) {
      return;
    }

    this.mDone = true;
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Reading complete. Final offset: ${this.mReadOffset}, Range max: ${this.mReadRange!.max}.`);
    this.clear();

    setTimeout(() => {
      if ( this.mDoneCallback ) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing done callback.`);
        this.mDoneCallback(this);
      }
    });
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mSerialQueue.enqueue(async () => {
      if ( this.mAborted || this.mDone ) {
        return;
      }

      MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Aborting loader. Error: ${error?.message || "No error provided."}`);

      this.mAborted = true;

      await this.clear();

      MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Loader marked as aborted. Final error state: ${error?.message || "None"}.`);

      if (this.mAbortedCallback) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing aborted callback with error: ${error?.message || "None"}.`);
        this.mAbortedCallback(this, error);
      }
    });
  }

  // 清理操作执行之前, 子类可以做一些自定义操作;
  protected onClearBefore() { }

  private async clear(): Promise<void> {
    this.onClearBefore();
    if ( this.mContent ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Clearing content.`);
      this.mContent.off('dataWritten');
      this.mContent.readwriteRelease();
      await this.mContent.closeRead();
      this.mContent = undefined;
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Cleared content.');
    }
    this.onClearAfter();
  }

  // 清理操作执行之后, 子类可以做一些自定义操作;
  protected onClearAfter() { }

  on(event: "newDataReadable" | "aborted" | "done", callback: Function): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Registering callback for event '${event}'.`);

    switch (event) {
      case 'newDataReadable':
        this.mNewDataReadableCallback = callback as (loader: IMCMediaContentLoader) => void;
        break;
      case 'aborted':
        this.mAbortedCallback = callback as (loader: IMCMediaContentLoader, error?: Error) => void;
        break;
      case 'done':
        this.mDoneCallback = callback as (loader: IMCMediaContentLoader) => void;
        break;
    }
  }

  off(event: "newDataReadable" | "aborted" | "done"): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Removing callback for event '${event}'.`);

    switch (event) {
      case 'newDataReadable':
        this.mNewDataReadableCallback = undefined;
        break;
      case 'aborted':
        this.mAbortedCallback = undefined;
        break;
      case 'done':
        this.mDoneCallback = undefined;
        break;
    }
  }
}