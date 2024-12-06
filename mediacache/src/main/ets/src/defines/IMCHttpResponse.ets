export interface IMCHttpResponse {
  readonly isHeadersSent: boolean;

  prepare(): Promise<void>;

  abort(error?: Error): Promise<void>;

  on(event: 'headersReceive', callback: (response: IMCHttpResponse, headers: string) => void | Promise<void>): void;
  off(event: 'headersReceive'): void;

  on(event: 'dataReceive', callback: (response: IMCHttpResponse, data: ArrayBuffer) => void | Promise<void>): void;
  off(event: 'dataReceive'): void;

  on(event: 'dataEnd', callback: (response: IMCHttpResponse) => void | Promise<void>): void;
  off(event: 'dataEnd'): void;

  on(event: 'aborted', callback: (response: IMCHttpResponse, error?: Error) => void | Promise<void>): void; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): void;
}