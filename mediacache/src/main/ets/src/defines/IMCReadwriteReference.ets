export interface IMCReadwriteReference<T> {
  readonly readwriteCount: number; // 读写计数

  readwriteRetain(): T; // 增加读写引用计数
  readwriteRelease(): void; // 释放读写引用计数
}