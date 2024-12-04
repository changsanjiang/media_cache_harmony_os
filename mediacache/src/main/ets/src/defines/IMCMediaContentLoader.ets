import { MCRange } from "../utils/MCRange";

/** 加载数据; */
export interface IMCMediaContentLoader {
  readonly isDone: boolean;
  readonly isAborted: boolean;
  readonly range: MCRange | undefined; // 需要加载的数据的范围(或者说是需要读取的数据的范围, 当这个范围的数据读取完毕后, loader的状态会变成 done);
  readonly offset: number; // 数据读取的偏移量;
  readonly readableLength: number; // 当前已加载可读取的数据长度;

  prepare(): Promise<void>;
  readData(buffer: ArrayBuffer): Promise<number>;
  seekToEndOfReadableRange(): Promise<number>; // 跳转到可读取的数据的尾部;
  abort(error?: Error): Promise<void>;

  on(event: 'prepared', callback: (loader: IMCMediaContentLoader, range: MCRange) => void): void;
  off(event: 'prepared'): void;

  // Event when new data is available for reading.
  on(event: 'dataLoaded', callback: (loader: IMCMediaContentLoader, length: number) => void): void;
  off(event: 'dataLoaded'): void;

  on(event: 'aborted', callback: (loader: IMCMediaContentLoader, error?: Error) => void): void;
  off(event: 'aborted'): void;

  on(event: 'done', callback: (loader: IMCMediaContentLoader) => void): void;
  off(event: 'done'): void;
}