import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCRange } from "../utils/MCRange";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";

export class MCMediaContentLoader implements IMCMediaContentLoader {
  private mPreparedCallback?: (loader: IMCMediaContentLoader, range: MCRange) => void = undefined;
  private mDataLoadedCallback?: (loader: IMCMediaContentLoader, length: number) => void = undefined;
  private mAbortedCallback?: (loader: IMCMediaContentLoader, error?: Error) => void = undefined;
  private mDoneCallback?: (loader: IMCMediaContentLoader) => void = undefined;
  private mOffset = 0;
  protected mDone = false;
  protected mAborted = false;
  private mContent?: IMCMediaContent = undefined;
  private mRange?: MCRange = undefined;

  get isDone(): boolean {
    return this.mDone;
  }

  get isAborted(): boolean {
    return this.mAborted;
  }

  get range(): MCRange | undefined {
    return this.mRange;
  }

  get readableLength(): number {
    if ( !this.mContent || !this.mRange || this.mAborted || this.mDone ) {
      return 0;
    }
    const offset = this.mContent.contentOffset;
    const length = this.mContent.length;
    const readableLength = Math.min((offset + length), this.mRange.max) - this.mOffset;
    return readableLength;
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => 'Starting preparation.');
    if (this.mAborted) {
      MCLogger.warn(MCLogModule.MCMediaDataReader, () => `Cannot prepare as the loader has been aborted.`);
      return;
    }

    try {
      await this.onPrepare();
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => 'Loader preparation complete.');
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error during preparation: ${(error as Error).message}`);
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
      this.mRange = range;
      this.mOffset = range.location;
      this.mContent.on('dataWritten', (content: IMCMediaContent, length: number) => this.dataWritten(content, length)); // 实现类通知抽象类可加载数据了;

      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Content is ready. Range: ${JSON.stringify(range)}, Content offset: ${content.contentOffset}, Done: ${this.mDone}.`);

      if (this.mPreparedCallback) {
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing prepared callback.`);
        this.mPreparedCallback(this, range);
      }

      if ( range.length === 0 ) {
        this.done();
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error in contentReady: ${(error as Error).message}`);
      this.abort(error);
      throw error as Error;
    }
  }

  private dataWritten(_: IMCMediaContent, length: number): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Data loaded: ${length} bytes.`);

    if ( !this.mDone && !this.mAborted && this.mDataLoadedCallback ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing dataLoaded callback.`);
      this.mDataLoadedCallback(this, length);
    }
  }

  private increaseOffset(length: number) {
    if ( length > 0 ) {
      this.mOffset += length;
      const done = this.mOffset === this.mRange!.max;

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Offset increased by ${length}, current offset: ${this.mOffset}. Range max: ${this.mRange!.max}.`);

      if ( done ) {
        this.done();
      }
    }
  }

  async readData(buffer: ArrayBuffer): Promise<number> {
    try {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Attempting to read data. Buffer size: ${buffer.byteLength}.`);

      if (!this.mContent) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'No content available for reading.');
        return 0;
      }

      if (this.mAborted) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Read aborted due to loader being aborted.');
        return 0;
      }

      if (this.mDone) {
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => 'Read operation ignored as the loader is already done.');
        return 0;
      }

      const maxReadable = Math.min(buffer.byteLength, this.mRange!.max - this.mOffset);
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Calculated max readable size: ${maxReadable}.`);

      // 执行读取操作
      const readLength = await this.mContent.readData(this.mOffset, buffer, maxReadable);
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Read ${readLength} bytes at offset ${this.mOffset}.`);

      this.increaseOffset(readLength);
      return readLength;
    } catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error reading data: ${(error as Error).message}`);
      this.abort(error);
      throw error as Error;
    }
  }

  async seekToEndOfReadableRange(): Promise<number> {
    try {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Attempting to seek to the end of the readable range.`);

      const len = this.readableLength;
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Seeked to the end of readable range. Total readable length: ${len}.`);

      this.increaseOffset(len);
      return len;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error seeking to the end of readable range: ${(error as Error).message}`);
      this.abort(error);
      throw error as Error;
    }
  }

  private done(): void {
    if ( this.mAborted || this.mDone ) {
      return;
    }

    this.mDone = true;
    MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Loading complete. Final offset: ${this.mOffset}, Range max: ${this.mRange!.max}.`);
    this.clear();

    if ( this.mDoneCallback ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing done callback.`);
      this.mDoneCallback(this);
    }
  }

  async abort(error?: Error | undefined): Promise<void> {
    if ( this.mAborted || this.mDone ) {
      return undefined;
    }

    MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Aborting loader. Error: ${error?.message || "No error provided."}`);

    this.mAborted = true;

    this.clear();

    MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Loader marked as aborted. Final error state: ${error?.message || "None"}.`);

    if (this.mAbortedCallback) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Executing aborted callback with error: ${error?.message || "None"}.`);
      this.mAbortedCallback(this, error);
    }
  }

  // 清理操作执行之前, 子类可以做一些自定义操作;
  protected onClearBefore() { }

  private clear() {
    this.onClearBefore();
    if ( this.mContent ) {
      this.mContent.off('dataWritten');
      this.mContent.readwriteRelease();
      this.mContent.closeRead();
      this.mContent = undefined;
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Cleared content.');
    }
    this.onClearAfter();
  }

  // 清理操作执行之后, 子类可以做一些自定义操作;
  protected onClearAfter() { }

  on(event: "prepared" | "dataLoaded" | "aborted" | "done", callback: Function): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Registering callback for event '${event}'.`);

    switch (event) {
      case 'prepared':
        this.mPreparedCallback = callback as (loader: IMCMediaContentLoader, range: MCRange) => void;
        break;
      case 'dataLoaded':
        this.mDataLoadedCallback = callback as (loader: IMCMediaContentLoader, length: number) => void;
        break;
      case 'aborted':
        this.mAbortedCallback = callback as (loader: IMCMediaContentLoader, error?: Error) => void;
        break;
      case 'done':
        this.mDoneCallback = callback as (loader: IMCMediaContentLoader) => void;
        break;
    }
  }

  off(event: "prepared" | "dataLoaded" | "aborted" | "done"): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Removing callback for event '${event}'.`);

    switch (event) {
      case 'prepared':
        this.mPreparedCallback = undefined;
        break;
      case 'dataLoaded':
        this.mDataLoadedCallback = undefined;
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