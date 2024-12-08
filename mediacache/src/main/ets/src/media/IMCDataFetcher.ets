export interface IMCDataFetcher {
  prepare(): Promise<void>
  abort(error?: Error): Promise<void>;

  on(event: 'responseReceive', callback: (reader: IMCDataFetcher, responseHeaders: string) => void | Promise<void>): void;
  off(event: 'responseReceive'): void;

  on(event: 'dataReceive', callback: (reader: IMCDataFetcher, data: ArrayBuffer) => void | Promise<void>): void;
  off(event: 'dataReceive'): void;

  on(event: 'dataEnd', callback: (reader: IMCDataFetcher) => void): void;
  off(event: 'dataEnd'): void;

  on(event: 'aborted', callback: (reader: IMCDataFetcher, error?: Error) => void): void; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): void;
}