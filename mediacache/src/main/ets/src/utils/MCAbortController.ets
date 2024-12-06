export class MCAbortController {
  private mSignal = new MCAbortSignal_();

  get signal(): MCAbortSignal {
    return this.mSignal;
  }

  abort(reason?: Error): void {
    return this.mSignal.abort(reason);
  }
}

export interface MCAbortSignal {
  readonly aborted: boolean
  readonly reason: Error | undefined
  addEventListener(event: 'aborted', callback: () => void): void;
  removeEventListener(event: 'aborted', callback: () => void): void;
}

class MCAbortSignal_ implements MCAbortSignal {
  private mAborted = false
  private mReason: Error | undefined = undefined
  private mListeners = new Array<Function>();

  get aborted(): boolean {
    return this.mAborted;
  }

  get reason(): Error | undefined  {
    return this.mReason;
  }

  addEventListener(_: "aborted", callback: () => void): void {
    if ( !this.mAborted ) this.mListeners.push(callback);
    else callback();
  }

  removeEventListener(_: "aborted", callback: () => void): void {
    const index = this.mListeners.indexOf(callback);
    if (index >= 0) {
      this.mListeners.splice(index, 1);
    }
  }

  abort(reason?: Error): void {
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
  }
}