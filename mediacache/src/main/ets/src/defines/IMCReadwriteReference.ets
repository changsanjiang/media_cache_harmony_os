export interface IMCReadwriteReference<T> {
  readonly readwriteCount: number; // 读写计数

  readwriteRetain(from?: string): T; // 增加读写引用计数
  readwriteRelease(from?: string): void; // 释放读写引用计数
}