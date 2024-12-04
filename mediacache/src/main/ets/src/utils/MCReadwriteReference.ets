import { IMCReadwriteReference } from "../defines/IMCReadwriteReference";

export class MCReadwriteReference<T> implements IMCReadwriteReference<T> {
  protected mReadwriteCount = 0;

  get readwriteCount(): number {
    return this.mReadwriteCount;
  }

  readwriteRetain(from?: string): T {
    if (from) {
      console.log(`[READWRITE] readwriteRetain called from: ${from}.`)
    }
    this.mReadwriteCount += 1;
    return this.getInstance();
  }

  readwriteRelease(from?: string): void {
    if (from) {
      console.log(`[READWRITE] readwriteRelease called from: ${from}.`)
    }

    if (this.mReadwriteCount <= 0) {
      throw new Error("Release called with zero references.");
    }

    this.mReadwriteCount -= 1;
    if ( this.mReadwriteCount == 0 ) {
      this.onReadwriteZeroReferences();
    }
  }

  // 获取当前对象；子类需实现此方法以返回具体类型的实例
  protected getInstance(): T {
    throw new Error("Method 'getInstance()' must be implemented in subclass.");
  }

  // 引用计数为零时的回调，子类可重写此方法进行清理操作
  protected onReadwriteZeroReferences(): void {

  }
}