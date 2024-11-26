import { IMCReadwriteReference } from "../defines/IMCReadwriteReference";
import { ArkTSUtils } from "@kit.ArkTS";
import MCLogger from "./MCLogger";

export class MCReadwriteReference<T> implements IMCReadwriteReference<T> {
  protected mReadwriteCount = 0;
  protected mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();

  get readwriteCount(): Promise<number> {
    return this.mLock.lockAsync(() => this.mReadwriteCount);
  }

  readwriteRetain(): Promise<T> {
    return this.mLock.lockAsync(() => this.readwriteRetain());
  }

  readwriteRelease(): Promise<void> {
    return this.mLock.lockAsync(() => this.readwriteRelease());
  }

  readwriteRetainUnsafe(): T {
    this.mReadwriteCount += 1;
    return this.getInstance();
  }

  readwriteReleaseUnsafe(): void {
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