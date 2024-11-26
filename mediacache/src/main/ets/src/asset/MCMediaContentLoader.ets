import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { ArkTSUtils } from "@kit.ArkTS";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCRange } from "../utils/MCRange";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";

export class MCMediaContentLoader implements IMCMediaContentLoader {
  private mPreparedCallback?: (loader: IMCMediaContentLoader, range: MCRange) => void = undefined;
  private mDataLoadedCallback?: (loader: IMCMediaContentLoader, length: number) => void = undefined;
  private mAbortedCallback?: (loader: IMCMediaContentLoader, error?: Error) => void = undefined;
  private mOffset = 0;
  protected mDone = false;
  protected mAborted = false;
  protected mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mContent?: IMCMediaContent = undefined;
  private mRange?: MCRange = undefined;

  get isDone(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mDone);
  }

  get isAborted(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAborted);
  }

  get range(): Promise<MCRange | undefined> {
    return this.mLock.lockAsync(() => this.mRange);
  }

  get readableLength(): Promise<number> {
    return this.mLock.lockAsync(() => this.getReadableLengthUnsafe());
  }

  prepare(): Promise<void> {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Preparing loader...');
    return this.mLock.lockAsync(async () => {
      try {
        await this.onPrepare();
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => 'Loader preparation complete.');
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error during preparation: ${(error as Error).message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  readData(buffer: ArrayBuffer): Promise<number> {
    return this.mLock.lockAsync(async () => {
      try {
        if ( !this.mContent || this.mAborted || this.mDone ) {
          MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Read aborted or loader is done.');
          return 0;
        }

        const readLength = await this.mContent.readData(this.mOffset, buffer, Math.min(buffer.byteLength, this.mRange!.max - this.mOffset));
        MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Read ${readLength} bytes at offset ${this.mOffset}.`);

        this.increaseOffset(readLength);
        return readLength;
      } catch (error) {
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => `Error reading data: ${(error as Error).message}`);
        this.abortUnsafe(error);
        throw error as Error;
      }
    });
  }

  seekToEndOfReadableRange(): Promise<number> {
    return this.mLock.lockAsync(async () => {
      const readableLength = await this.getReadableLengthUnsafe();
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Seeked to the end of readable range. Length: ${readableLength}.`);
      this.increaseOffset(readableLength);
      return readableLength;
    });
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mLock.lockAsync(() => this.abortUnsafe(error));
  }

  on(event: "prepared" | "dataLoaded" | "aborted", callback: ((loader: IMCMediaContentLoader, readRange: MCRange) => void) | ((loader: IMCMediaContentLoader, length: number) => void) | ((loader: IMCMediaContentLoader, error?: Error | undefined) => void)): Promise<void> {
    return this.mLock.lockAsync(() => {
      switch (event) {
        case 'prepared': {
          this.mPreparedCallback = callback as (loader: IMCMediaContentLoader, range: MCRange) => void;
        }
          break;
        case 'dataLoaded': {
          this.mDataLoadedCallback = callback as (loader: IMCMediaContentLoader, length: number) => void;
        }
          break;
        case 'aborted': {
          this.mAbortedCallback = callback as (loader: IMCMediaContentLoader, error?: Error) => void;
        }
          break;
      }

      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Registered "${event}" callback.`);
    });
  }

  off(event: "prepared" | "dataLoaded" | "aborted"): Promise<void> {
    return this.mLock.lockAsync(() => {
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
      }

      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Unregistered "${event}" callback.`);
    });
  }

  /// 实现类在准备好 content 之后, 调用该方法通知抽象类;
  ///
  /// 实现类通知抽象类已准备好 content;
  /// 调用前请对 content 做一次 readwriteRetain 操作, 防止被提前 release; 之后不需要外部调用 release, 抽象类会在读取操作结束后进行清理操作;
  protected contentReady(content: IMCMediaContent, range: MCRange) {
    this.mLock.lockAsync(() => {
      if ( this.mAborted ) {
        MCLogger.warn(MCLogModule.MCMediaContentLoader, () => 'Content ready event ignored due to aborted loader.');
        return undefined;
      }
      if ( range.location > content.contentOffset ) {
        const errorMessage = `Invalid range location: ${range.location} exceeds content offset ${content.contentOffset}.`;
        MCLogger.error(MCLogModule.MCMediaContentLoader, () => errorMessage);
        throw new Error(errorMessage);
      }

      this.mContent = content;
      this.mRange = range;
      this.mOffset = range.location;
      this.mDone = range.length === 0;
      this.mContent.on('dataWritten', this.onDataLoaded); // 实现类通知抽象类可加载数据了;
      MCLogger.info(MCLogModule.MCMediaContentLoader, () => `Content ready. Range: ${JSON.stringify(range)}.`);
      return this.mPreparedCallback;
    }).then((callback) => {
      if ( callback != undefined ) callback?.(this, range);
    });
  }

  protected onPrepare(): Promise<void> {
    throw new Error("Method 'onPrepare()' must be implemented in subclass. Ensure your subclass overrides this method with necessary preparation logic.");
  }

  // 清理操作执行之前, 子类可以做一些自定义操作;
  protected onClearBefore() { }

  // 清理操作执行之后, 子类可以做一些自定义操作;
  protected onClearAfter() { }

  protected abortUnsafe(error?: Error | undefined): void {
    if ( this.mAborted || this.mDone ) {
      return undefined;
    }

    MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Aborting loader with error: ${error?.message}`);

    this.mAborted = true;

    this.clear();

    MCLogger.warn(MCLogModule.MCMediaContentLoader, () => `Loader aborted with error: ${error?.message}`);

    Promise.resolve(this.mAbortedCallback).then((callback) => callback?.(this, error));
  }

  private clear() {
    this.onClearBefore();
    if ( this.mContent ) {
      this.mContent.off('dataWritten', this.onDataLoaded);
      this.mContent.readwriteRelease();
      this.mContent.closeRead();
      this.mContent = undefined;
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'Cleared content.');
    }
    this.onClearAfter();
  }

  private onDataLoaded(_: IMCMediaContent, length: number): void {
    this.mLock.lockAsync(() => !this.mDone && !this.mAborted ? this.mDataLoadedCallback : undefined).then((callback) => callback?.(this, length));

    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Data loaded: ${length} bytes.`);
  }

  private async getReadableLengthUnsafe(): Promise<number> {
    if ( !this.mContent || !this.mRange || this.mAborted || this.mDone ) {
      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => 'No readable data available.');
      return 0;
    }
    const offset = this.mContent.contentOffset;
    const length = await this.mContent.length;
    const readableLength = Math.min((offset + length), this.mRange.max) - this.mOffset;
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Readable length: ${readableLength}.`);
    return readableLength;
  }

  private increaseOffset(length: number) {
    if ( length > 0 ) {
      this.mOffset += length;
      this.mDone = this.mOffset === this.mRange!.max;

      MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Increased offset by ${length}, current offset: ${this.mOffset}.`);
      if ( this.mDone ) {
        MCLogger.info(MCLogModule.MCMediaContentLoader, () => 'Loading complete.');
        this.clear();
      }
    }
  }
}