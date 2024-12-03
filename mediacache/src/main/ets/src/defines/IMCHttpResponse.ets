import { IMCHttpRequest } from "./IMCHttpRequest";

export interface IMCHttpResponse {
  readonly isDone: boolean;
  readonly isAborted: boolean;
  readonly isHeadersSent: boolean;

  prepare(proxyRequest: IMCHttpRequest): Promise<void>
  readData(): Promise<string | ArrayBuffer | undefined>;
  abort(error?: Error): Promise<void>; // abort 不仅仅是外部可以调用, 当内部执行出错时也会调用abort;

  on(event: 'newDataAvailable', callback: (response: IMCHttpResponse) => void): void;
  off(event: 'newDataAvailable'): void;

  on(event: 'aborted', callback: (response: IMCHttpResponse, error?: Error) => void): void; // 内部执行出错时也会调用 abort;
  off(event: 'aborted'): void;
}