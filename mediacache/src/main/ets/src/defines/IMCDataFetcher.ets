import { IMCHttpResponseHeaders } from "./IMCHttpResponseHeaders";

export interface IMCDataFetcher {
  /** 是否已准备就绪, 可以开始读取数据了; */
  readonly isReady: boolean;
  /** 是否已读取结束或 aborted; */
  readonly isCompleted: boolean;
  readonly isAborted: boolean;
  readonly isDataEnd: boolean;

  /** 准备就绪后可以获取; */
  readonly offset: number;
  /** 当前内部已加载的数据, 外部还未读取的数据量, 可通过 read 方法进行读取; */
  readonly readableLength: number;

  /** 返回响应头; */
  prepare(): Promise<IMCHttpResponseHeaders>;

  /** 拉取数据，或 undefined 表示当前不可读或结束; */
  read(capacity: number): Promise<ArrayBuffer | undefined>;

  /** 略过数据读取; 只允许在当前可读范围内 seek; */
  seek(offset: number): boolean;

  abort(error?: Error): void;

  /** 有新数据可读取时回调; */
  on(event: 'newDataReadable', callback: (fetcher: IMCDataFetcher) => void): void;
  on(event: 'aborted', callback: (fetcher: IMCDataFetcher, error?: Error) => void): void;
  on(event: 'dataEnd', callback: (fetcher: IMCDataFetcher) => void): void;

  off(event: 'newDataReadable'): void;
  off(event: 'aborted'): void;
  off(event: 'dataEnd'): void;
}