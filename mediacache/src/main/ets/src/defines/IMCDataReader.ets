export interface IMCDataReader {
  readonly responseHeaders: string | undefined;
  readonly readableLength: number; // 当前已准备好的可进行读取的数据的长度;
  readonly isDone: boolean;
  readonly isAborted: boolean;

  prepare(): Promise<void>
  readData(buffer: ArrayBuffer): Promise<number>;
  seekToEndOfReadableRange(): Promise<number>; // 跳转到当前可读范围的尾部，并返回跳转了的长度(readableLength);
  abort(error?: Error): Promise<void>;

  on(event: 'responseReady', callback: (reader: IMCDataReader, responseHeaders: string) => void): void;
  off(event: 'responseReady'): void;

  on(event: 'newDataReadable', callback: (reader: IMCDataReader) => void): void;
  off(event: 'newDataReadable'): void;

  on(event: 'aborted', callback: (reader: IMCDataReader, error?: Error) => void): void; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): void;

  on(event: 'done', callback: (reader: IMCDataReader) => void): void;
  off(event: 'done'): void;
}