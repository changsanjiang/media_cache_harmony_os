import { IMCHttpRequest } from "./MCHttpRequest";

export interface IMCHttpResponse {
  readonly isDone: Promise<boolean>;
  prepare(proxyRequest: IMCHttpRequest): Promise<void>
  readData(): Promise<string | ArrayBuffer | undefined>;
  abort(): Promise<void>;
  on(event: 'newDataAvailable', callback: (response: IMCHttpResponse) => void): void;
}

export class MCHttpResponse implements IMCHttpResponse {
  get isDone(): Promise<boolean> {
    return Promise.resolve(false);
  }

  prepare(proxyRequest: IMCHttpRequest): Promise<void> {
    throw new Error("Method not implemented.");
  }

  readData(): Promise<string | ArrayBuffer | undefined> {
    throw new Error("Method not implemented.");
  }

  abort(): Promise<void> {
    throw new Error("Method not implemented.");
  }

  on(event: "newDataAvailable", callback: (response: IMCHttpResponse) => void): void {
    throw new Error("Method not implemented.");
  }
}