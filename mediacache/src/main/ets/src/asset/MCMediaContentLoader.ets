import { IMCMediaContentLoader } from "../common/IMCMediaContentLoader";
import { ArkTSUtils } from "@kit.ArkTS";
import { IMCMediaContent } from "../common/IMCMediaContent";
import { MCRange } from "../utils/MCRange";

export class MCMediaContentLoader implements IMCMediaContentLoader {
  private mDone = false;
  private mAborted = false;
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mDataLoadedCallback?: (loader: IMCMediaContentLoader, length: number) => void = undefined;
  private mAbortedCallback?: (loader: IMCMediaContentLoader, error?: Error) => void = undefined;
  private mContent?: IMCMediaContent = undefined;
  private mLoadRange = MCRange.zero;
  private mOffset = 0;

  get isDone(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mDone);
  }

  get isAborted(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAborted);
  }

  prepare(): Promise<void> {
    return this.mLock.lockAsync(() => this.onPrepare());
  }

  readData(buffer: ArrayBuffer): Promise<number> {
    return this.mLock.lockAsync(async () => {
      if ( !this.mContent || this.mAborted || this.mDone ) {
        return 0;
      }

      const len = await this.mContent.readData(this.mOffset, buffer, Math.min(buffer.byteLength, this.mLoadRange.max - this.mOffset));
      if ( len > 0 ) {
        this.mOffset += len;
        this.mDone = this.mOffset === this.mLoadRange.max;
        if ( this.mDone ) {
          this.clear();
        }
      }
      return len;
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

  on(event: "dataLoaded" | "aborted", callback: ((loader: IMCMediaContentLoader, length: number) => void) | ((loader: IMCMediaContentLoader, error?: Error | undefined) => void)): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( event === 'dataLoaded' ) {
        this.mDataLoadedCallback = callback as (loader: IMCMediaContentLoader, length: number) => void;
      }
      else if ( event === 'aborted') {
        this.mAbortedCallback = callback as (loader: IMCMediaContentLoader, error?: Error) => void;
      }
    });
  }

  off(event: "dataLoaded" | "aborted"): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( event === 'dataLoaded' ) {
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
  protected contentReady(content: IMCMediaContent, loadRange: MCRange) {
    this.mLock.lockAsync(() => {
      if ( !this.mAborted ) {
        this.mContent = content;
        this.mLoadRange = loadRange;
        this.mOffset = loadRange.location;
        this.mContent.on('dataWritten', this.onDataLoaded); // 实现类通知抽象类可加载数据了;
        return content.length;
      }
      return 0;
    }).then((loadableLength) => {
      if ( loadableLength != 0 ) this.onDataLoaded(content, loadableLength);
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
    if ( this.mContent ) {
      this.onClearBefore();
      this.mContent.off('dataWritten', this.onDataLoaded);
      this.mContent.readwriteRelease();
      this.mContent.closeRead();
      this.onClearAfter();
    }
  }
}