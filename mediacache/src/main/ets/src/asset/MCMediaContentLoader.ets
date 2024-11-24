import { IMCMediaContentLoader } from "../common/IMCMediaContentLoader";
import { ArkTSUtils } from "@kit.ArkTS";
import { IMCMediaContent } from "../common/IMCMediaContent";

export class MCMediaContentLoader implements IMCMediaContentLoader {
  private mDone = false;
  private mAborted = false;
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mContent?: IMCMediaContent = undefined;
  private mDataLoadedCallback?: (loader: IMCMediaContentLoader, length: number) => void = undefined;
  private mAbortedCallback?: (loader: IMCMediaContentLoader, error?: Error) => void = undefined;
  private mOffset = 0;

  get isDone(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mDone);
  }

  get isAborted(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAborted);
  }

  prepare(): Promise<void> {
    throw new Error("Method not implemented.");
  }

  readData(buffer: ArrayBuffer): Promise<number> {
    return this.mLock.lockAsync(async () => {
      if ( !this.mContent || this.mAborted || this.mDone ) {
        return 0;
      }

      const len = await this.mContent.readData(this.mOffset, buffer);
      if ( len > 0 ) this.mOffset += len;

      // TODO: update done state;

      return len;
    });
  }

  abort(error?: Error | undefined): Promise<void> {
    throw new Error("Method not implemented.");
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

  protected onContentReady(content: IMCMediaContent) {
    this.mLock.lockAsync(() => {
      if ( !this.mAborted ) {
        this.mContent = content;
        this.mContent.on('dataWritten', this.onDataLoaded);
        return content.length;
      }
      return 0;
    }).then((length) => {
      if ( length != 0 ) this.onDataLoaded(content, length);
    });
  }

  private onDataLoaded(_: IMCMediaContent, length: number): void {
    this.mLock.lockAsync(() => !this.mDone && !this.mAborted ? this.mDataLoadedCallback : undefined).then((callback) => callback?.(this, length));
  }
}