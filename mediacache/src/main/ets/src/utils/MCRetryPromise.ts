enum PromiseState {
  PENDING,
  FULFILLED,
  REJECTED,
}

/// 返回可重试的 Promise; 执行出错时, 新的订阅将会进行重试;
export class MCRetryPromise<T> implements Promise<T> {
  private mExecutor?: (resolve: (value: T | PromiseLike<T>) => void, reject: (reason?: any) => void) => void
  private mPromise: Promise<T>
  private mState = PromiseState.PENDING

  constructor(executor: (resolve: (value: T | PromiseLike<T>) => void, reject: (reason?: any) => void) => void) {
    this.mExecutor = executor;
    this.retry();
  }

  then<TResult1 = T, TResult2 = never>(onfulfilled?: ((value: T) => TResult1 | PromiseLike<TResult1>) | null | undefined, onrejected?: ((reason: any) => TResult2 | PromiseLike<TResult2>) | null | undefined): Promise<TResult1 | TResult2> {
    return this.ensure().then(onfulfilled, onrejected);
  }

  catch<TResult = never>(onrejected?: ((reason: any) => TResult | PromiseLike<TResult>) | null | undefined): Promise<T | TResult> {
    return this.ensure().catch(onrejected);
  }

  finally(onfinally?: (() => void) | null | undefined): Promise<T> {
    return this.ensure().finally(onfinally);
  }

  [Symbol.toStringTag]: string = 'MCRetryablePromiseObject'

  private ensure(): Promise<T> {
    return (this.mState != PromiseState.REJECTED) ? this.mPromise : this.retry();
  }

  private retry(): Promise<T> {
    this.mPromise = new Promise(this.mExecutor).then((value) => {
      this.mState = PromiseState.FULFILLED;
      this.mExecutor = undefined;
      return value;
    }, (error) => {
      this.mState = PromiseState.REJECTED;
      return Promise.reject(error);
    });
    return this.mPromise;
  }
}