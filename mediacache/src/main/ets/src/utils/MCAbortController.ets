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
  readonly isAborted: boolean
  readonly reason: Error | undefined
  addEventListener(event: 'aborted', callback: (error: Error) => void | Promise<void>): void;
  removeEventListener(event: 'aborted', callback: (error: Error) => void | Promise<void>): void;
}

class MCAbortSignal_ implements MCAbortSignal {
  private mAborted = false
  private mReason: Error | undefined = undefined
  private mListeners = new Array<(error: Error) => void | Promise<void>>();

  get isAborted(): boolean {
    return this.mAborted;
  }

  get reason(): Error | undefined  {
    return this.mReason;
  }

  addEventListener(_: "aborted", callback: (error: Error) => void | Promise<void>): void {
    if ( !this.mAborted ) this.mListeners.push(callback);
    else callback(this.mReason!);
  }

  removeEventListener(_: "aborted", callback: (error: Error) => void | Promise<void>): void {
    const index = this.mListeners.indexOf(callback);
    if (index >= 0) {
      this.mListeners.splice(index, 1);
    }
  }

  async abort(reason?: Error): Promise<void> {
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
      await Promise.all(this.mListeners.map((listener) => listener(this.mReason!)));
      this.mListeners.length = 0;
    }
  }
}