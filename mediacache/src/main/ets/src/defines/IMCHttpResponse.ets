export interface IMCHttpResponse {
  readonly isHeadersSent: boolean;

  prepare(): Promise<void>;

  abort(error?: Error): Promise<void>;

  on(event: 'dataReceive', callback: (response: IMCHttpResponse, data: string | ArrayBuffer) => void | Promise<void>): void;
  off(event: 'dataReceive'): void;

  on(event: 'aborted', callback: (response: IMCHttpResponse, error?: Error) => void | Promise<void>): void; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): void;

  on(event: 'done', callback: (response: IMCHttpResponse) => void | Promise<void>): void;
  off(event: 'done'): void;
}