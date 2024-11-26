import { IMCMediaContentLoader } from "../defines/IMCMediaContentLoader";
import { ArkTSUtils } from "@kit.ArkTS";
import { IMCMediaContent } from "../defines/IMCMediaContent";
import { MCRange } from "../utils/MCRange";

export class MCMediaContentLoader implements IMCMediaContentLoader {
  private mPreparedCallback?: (loader: IMCMediaContentLoader, range: MCRange) => void = undefined;
  private mDataLoadedCallback?: (loader: IMCMediaContentLoader, length: number) => void = undefined;
  private mAbortedCallback?: (loader: IMCMediaContentLoader, error?: Error) => void = undefined;
  private mOffset = 0;
  protected mDone = false;
  protected mAborted = false;
  protected mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  protected mContent?: IMCMediaContent = undefined;
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
    return this.mLock.lockAsync(() => this.onPrepare());
  }

  readData(buffer: ArrayBuffer): Promise<number> {
    return this.mLock.lockAsync(async () => {
      if ( !this.mContent || this.mAborted || this.mDone ) {
        return 0;
      }

      const readLength = await this.mContent.readData(this.mOffset, buffer, Math.min(buffer.byteLength, this.mRange!.max - this.mOffset));
      this.increaseOffset(readLength);
      return readLength;
    });
  }

  seekToEndOfReadableRange(): Promise<number> {
    return this.mLock.lockAsync(async () => {
      const readableLength = await this.getReadableLengthUnsafe();
      this.increaseOffset(readableLength);
      return readableLength;
    });
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( this.mAborted || this.mDone ) {
        return undefined;
      }
      this.mAborted = true;
      this.clear();
      return this.mAbortedCallback;
    }).then((callback) => callback?.(this, error));
  }

  on(event: "prepared" | "dataLoaded" | "aborted", callback: ((loader: IMCMediaContentLoader, readRange: MCRange) => void) | ((loader: IMCMediaContentLoader, length: number) => void) | ((loader: IMCMediaContentLoader, error?: Error | undefined) => void)): Promise<void> {
    return this.mLock.lockAsync(() => {
      if      ( event === 'prepared' ) {
        this.mPreparedCallback = callback as (loader: IMCMediaContentLoader, range: MCRange) => void;
      }
      else if ( event === 'dataLoaded' ) {
        this.mDataLoadedCallback = callback as (loader: IMCMediaContentLoader, length: number) => void;
      }
      else if ( event === 'aborted') {
        this.mAbortedCallback = callback as (loader: IMCMediaContentLoader, error?: Error) => void;
      }
    });
  }

  off(event: "prepared" | "dataLoaded" | "aborted"): Promise<void> {
    return this.mLock.lockAsync(() => {
      if      ( event === 'prepared' ) {
        this.mPreparedCallback = undefined;
      }
      else if ( event === 'dataLoaded' ) {
        this.mDataLoadedCallback = undefined;
      }
      else if ( event === 'aborted' ) {
        this.mAbortedCallback = undefined;
      }
    });
  }

  /// 实现类在准备好 content 之后, 调用该方法通知抽象类;
  ///
  /// 实现类通知抽象类已准备好 content;
  /// 调用前请对 content 做一次 readwriteRetain 操作, 防止被提前 release; 之后不需要外部调用 release, 抽象类会在读取操作结束后进行清理操作;
  protected contentReady(content: IMCMediaContent, range: MCRange) {
    this.mLock.lockAsync(() => {
      if ( this.mAborted ) {
        return undefined;
      }
      if ( range.location > content.contentOffset ) {
        throw new Error(`Invalid range location: ${range.location} exceeds content offset ${content.contentOffset}.`);
      }
      this.mContent = content;
      this.mRange = range;
      this.mOffset = range.location;
      this.mContent.on('dataWritten', this.onDataLoaded); // 实现类通知抽象类可加载数据了;
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

  private onDataLoaded(_: IMCMediaContent, length: number): void {
    this.mLock.lockAsync(() => !this.mDone && !this.mAborted ? this.mDataLoadedCallback : undefined).then((callback) => callback?.(this, length));
  }

  private clear() {
    this.onClearBefore();
    if ( this.mContent ) {
      this.mContent.off('dataWritten', this.onDataLoaded);
      this.mContent.readwriteRelease();
      this.mContent.closeRead();
    }
    this.onClearAfter();
  }

  private async getReadableLengthUnsafe(): Promise<number> {
    if ( !this.mContent || !this.mRange || this.mAborted || this.mDone ) {
      return 0;
    }
    const offset = this.mContent.contentOffset;
    const length = await this.mContent.length;
    const readableLength = Math.min((offset + length), this.mRange.max) - this.mOffset;
    return readableLength;
  }

  private increaseOffset(length: number) {
    if ( length > 0 ) {
      this.mOffset += length;
      this.mDone = this.mOffset === this.mRange!.max;
      if ( this.mDone ) {
        this.clear();
      }
    }
  }
}