export interface IMCReadwriteReference<T> {
  readonly readwriteCount: Promise<number>;

  readwriteRetain(): Promise<T>;
  readwriteRelease(): Promise<void>;
}