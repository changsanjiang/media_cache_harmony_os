import { IMCDataResponse } from "./IMCDataResponse";

export interface IMCDataReader {
  readonly readableLength: Promise<number>; // 当前已准备好的可进行读取的数据的长度;
  readonly response: Promise<IMCDataResponse | undefined>;
  readonly isDone: Promise<boolean>;
  readonly isAborted: Promise<boolean>;

  prepare(): Promise<void>
  readData(buffer: ArrayBuffer): Promise<number>;
  seekToEndOfReadableRange(): Promise<number>; // 跳转到当前可读范围的尾部，并返回跳转了的长度(readableLength);
  abort(error?: Error): Promise<void>;

  on(event: 'responseReady', callback: (reader: IMCDataReader, response: IMCDataResponse) => void): Promise<void>;
  off(event: 'responseReady'): Promise<void>;

  on(event: 'newDataReadable', callback: (reader: IMCDataReader) => void): Promise<void>;
  off(event: 'newDataReadable'): Promise<void>;

  on(event: 'aborted', callback: (reader: IMCDataReader, error?: Error) => void): Promise<void>; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): Promise<void>;

  on(event: 'done', callback: (reader: IMCDataReader) => void): Promise<void>;
  off(event: 'done'): Promise<void>;
}