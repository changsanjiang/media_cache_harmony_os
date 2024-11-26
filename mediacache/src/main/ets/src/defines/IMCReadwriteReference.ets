export interface IMCReadwriteReference<T> {
  readonly readwriteCount: Promise<number>; // 读写计数

  readwriteRetain(): Promise<T>; // 增加读写引用计数
  readwriteRelease(): Promise<void>; // 释放读写引用计数

  // 无锁保护
  readwriteRetainUnsafe(): T;
  readwriteReleaseUnsafe(): void;
}