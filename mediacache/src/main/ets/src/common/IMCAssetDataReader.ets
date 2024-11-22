import { IMCAssetDataResponse } from "./IMCAssetDataResponse";

export interface IMCAssetDataReader {
  readonly readableLength: Promise<number>;
  readonly response: Promise<IMCAssetDataResponse | undefined>;
  readonly isDone: Promise<boolean>;
  readonly isAborted: Promise<boolean>;

  prepare(): Promise<void>
  readData(capacity: number): Promise<ArrayBuffer | undefined>;
  seekToEndOfReadableRange(): Promise<number>; // 跳转到当前可读范围的尾部，并返回跳转了的长度(readableLength);
  abort(error?: Error): Promise<void>;

  on(event: 'responseReady', callback: (reader: IMCAssetDataReader, response: IMCAssetDataResponse) => void): Promise<void>;
  off(event: 'responseReady'): Promise<void>;

  on(event: 'newDataReadable', callback: (reader: IMCAssetDataReader) => void): Promise<void>;
  off(event: 'newDataReadable'): Promise<void>;

  on(event: 'aborted', callback: (reader: IMCAssetDataReader, error?: Error) => void): Promise<void>; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): Promise<void>;
}