import { IMCHttpRequest } from "./MCHttpRequest";
import { ArkTSUtils } from "@kit.ArkTS";

export interface IMCHttpResponse {
  readonly isDone: Promise<boolean>;
  prepare(proxyRequest: IMCHttpRequest): Promise<void>
  readData(): Promise<string | ArrayBuffer | undefined>;
  abort(): Promise<void>;
  on(event: 'newDataAvailable', callback: (response: IMCHttpResponse) => void): Promise<void>;
  off(event: 'newDataAvailable'): Promise<void>;
}

export class MCHttpResponse implements IMCHttpResponse {
  private mProxyRequest?: IMCHttpRequest = undefined;
  private mNewDataCallback?: (response: IMCHttpResponse) => void = undefined;
  private mAborted = false;
  private mDone = false;
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();

  get isDone(): Promise<boolean> {
    return this.mLock.lockAsync(() => this.mDone);
  }

  prepare(proxyRequest: IMCHttpRequest): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( this.mProxyRequest ) {
        throw new Error("当前已经有一个请求正在处理");
      }

      this.mProxyRequest = proxyRequest;

      // TODO: handle request;
    });
  }

  readData(): Promise<string | ArrayBuffer | undefined> {
    throw new Error("Method not implemented.");
  }

  abort(): Promise<void> {
    return this.mLock.lockAsync(() => {
      if ( this.mAborted || this.mDone ) {
        return;
      }

      this.mAborted = true;
      // TODO: handle abort;
    });
  }

  on(_: "newDataAvailable", callback: (response: IMCHttpResponse) => void): Promise<void> {
    return this.mLock.lockAsync(() => { this.mNewDataCallback = callback; });
  }

  off(_: 'newDataAvailable'): Promise<void> {
    return this.mLock.lockAsync(() => { this.mNewDataCallback = undefined; });
  }
}