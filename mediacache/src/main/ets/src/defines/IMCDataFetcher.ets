export interface IMCDataFetcher {
  prepare(): Promise<void>
  abort(error?: Error): Promise<void>;

  on(event: 'responseReceive', callback: (fetcher: IMCDataFetcher, responseHeaders: string) => void | Promise<void>): void;
  off(event: 'responseReceive'): void;

  on(event: 'dataReceive', callback: (fetcher: IMCDataFetcher, offset: number, data: ArrayBuffer) => void | Promise<void>): void;
  off(event: 'dataReceive'): void;

  on(event: 'dataEnd', callback: (fetcher: IMCDataFetcher) => void): void;
  off(event: 'dataEnd'): void;

  on(event: 'aborted', callback: (fetcher: IMCDataFetcher, error?: Error) => void): void; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): void;
}