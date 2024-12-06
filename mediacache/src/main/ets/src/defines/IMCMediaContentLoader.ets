export type MCMediaContentDecryptHandler = (offset: number, data: ArrayBuffer, len: number) => number | Promise<number>;

/** 加载数据; */
export interface IMCMediaContentLoader {
  readonly isDone: boolean;
  readonly isAborted: boolean;

  prepare(): Promise<void>;
  readData(decrypt?: MCMediaContentDecryptHandler): Promise<ArrayBuffer | undefined>;
  seekToEndOfReadableRange(): Promise<number>; // 跳转到可读取的数据的尾部;
  abort(error?: Error): Promise<void>;

  on(event: 'newDataReadable', callback: (loader: IMCMediaContentLoader) => void): void;
  off(event: 'newDataReadable'): void;

  on(event: 'aborted', callback: (loader: IMCMediaContentLoader, error?: Error) => void): void;
  off(event: 'aborted'): void;

  on(event: 'done', callback: (loader: IMCMediaContentLoader) => void): void;
  off(event: 'done'): void;
}