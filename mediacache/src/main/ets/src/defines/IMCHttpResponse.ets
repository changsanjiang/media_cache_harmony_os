export interface IMCHttpResponse {
  /** 是否已准备就绪, 可以开始读取数据了; */
  readonly isReady: boolean;
  /** 是否已读取结束或 aborted; */
  readonly isCompleted: boolean;

  readonly isDone: boolean;

  /** 返回响应头 headers; */
  prepare(): Promise<string>;

  /** 拉取数据，或 undefined 表示当前不可读或结束; */
  read(capacity: number): Promise<ArrayBuffer | undefined>;

  abort(error?: Error): void;

  /** 有新数据可读取时回调; */
  on(event: 'newDataReadable', callback: (response: IMCHttpResponse) => void): void;
  on(event: 'aborted', callback: (response: IMCHttpResponse, error?: Error) => void): void;
  on(event: 'done', callback: (response: IMCHttpResponse) => void): void;

  off(event: 'newDataReadable'): void;
  off(event: 'aborted'): void;
  off(event: 'done'): void;
}