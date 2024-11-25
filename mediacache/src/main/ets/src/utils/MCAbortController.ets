import { ArkTSUtils } from "@kit.ArkTS";

export class MCAbortController {
  private mSignal = new MCAbortSignal_();

  get signal(): MCAbortSignal {
    return this.mSignal;
  }

  abort(reason?: Error): Promise<void> {
    return this.mSignal.abort(reason);
  }
}

export interface MCAbortSignal {
  readonly aborted: Promise<boolean>
  readonly reason: Promise<Error | undefined>
  addEventListener(event: 'aborted', callback: () => void): Promise<void>;
}

class MCAbortSignal_ implements MCAbortSignal {
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mAborted = false
  private mReason: Error | undefined = undefined
  private mListeners = new Array<Function>();

  get aborted(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mAborted);
  }

  get reason(): Promise<Error | undefined>  {
    return this.mLock.lockAsync(() => this.mReason);
  }

  addEventListener(_: "aborted", callback: () => void): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( !this.mAborted ) this.mListeners.push(callback);
      else callback();
    });
  }

  abort(reason?: Error): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( !this.mAborted ) {
        this.mAborted = true;
        if ( reason ) {
          this.mReason = reason;
        }
        else {
          let abortErr = new Error('The operation was aborted.');
          abortErr.name = 'ABORT_ERR';
          this.mReason = abortErr;
        }
        this.mListeners.forEach((listener) => { listener(); });
        this.mListeners.length = 0;
      }
    });
  }
}