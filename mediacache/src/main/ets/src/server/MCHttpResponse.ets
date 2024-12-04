import { IMCDataReader } from "../defines/IMCDataReader";
import MCLogger from "../utils/MCLogger";
import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCHttpResponse } from "../defines/IMCHttpResponse";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAssetReader } from "../asset/MCAssetReader";

export class MCHttpResponse implements IMCHttpResponse {
  private mClientId: number;
  private mRequest: IMCHttpRequest
  private mDataReader?: IMCDataReader = undefined;
  private mHeadersSent = false;
  private mDataReceiveCallback?: (response: IMCHttpResponse, data: string | ArrayBuffer) => void | Promise<void> = undefined;
  private mAbortedCallback?: (response: IMCHttpResponse, error?: Error) => void | Promise<void> = undefined;
  private mDoneCallback?: (response: IMCHttpResponse) => void | Promise<void> = undefined;
  private mReading = false;
  private mAborted = false;
  private mDone = false;

  constructor(clientId: number, request: IMCHttpRequest) {
    this.mClientId = clientId;
    this.mRequest = request;
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${clientId}] Instance created for request: ${JSON.stringify(request)}.`);
  }

  get isHeadersSent(): boolean {
    return this.mHeadersSent;
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing response for request: ${JSON.stringify(this.mRequest)}`);

    this.mDataReader = new MCAssetReader(this.mClientId, {
      requestTarget: this.mRequest.requestTarget,
      headers: this.mRequest.headers
    });
    this.mDataReader.on('responseReady', (_) => this.dataReceive());
    this.mDataReader.on('newDataReadable', (_) => this.dataReceive());
    this.mDataReader.on('aborted', (_, error) => this.abort(error));
    this.mDataReader.prepare();
  }

  private async dataReceive(): Promise<void> {
    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Starting dataReceive: Aborted=${this.mAborted}, Done=${this.mDone}, Reading=${this.mReading}.`);

    if ( this.mAborted || this.mDone || this.mReading ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Skipping dataReceive: Aborted=${this.mAborted}, Done=${this.mDone}, Reading=${this.mReading}.`);
      return;
    }

    const reader = this.mDataReader;
    if ( !reader ) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] No data reader found while attempting to read data.`);
      return undefined;
    }

    this.mReading = true;
    try {
      const callback = this.mDataReceiveCallback;
      while (!this.mAborted && !this.mDone && callback) {
        // 先发送响应头消息;
        if (!this.mHeadersSent) {
          const responseHeaders = reader.responseHeaders;
          if ( !responseHeaders ) {
            break;
          }
          await callback(this, responseHeaders);
          this.mHeadersSent = true;
          MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Response headers has been sent: \n${responseHeaders}`);
        }
        // 再发送响应的 body 数据;
        else {
          const buffer = await reader.readData();
          if ( !buffer ) {
            break;
          }

          await callback(this, buffer);
          MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Data chunk read (${buffer.byteLength} bytes).`);
        }
      }
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Error during data read: ${error.message}`);
      this.abort(error as Error);
      throw error as Error;
    }
    finally {
      this.mReading = false;
      if ( reader.isDone ) {
        MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] All data has been successfully read. `);
        this.done();
        return;
      }
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] No data available for reading. Waiting for the next callback...`);
    }
  }

  async abort(error?: Error | undefined): Promise<void> {
    if ( this.mAborted || this.mDone ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Abort ignored: Aborted=${this.mAborted}, Done=${this.mDone}.`);
      return;
    }

    MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Aborting MCHttpResponse${error ? ` due to error: ${error.message}` : ''}.`);

    this.mAborted = true;

    this.clear(true, error);

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || 'None'}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private done(): void {
    if ( this.mAborted || this.mDone ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Done ignored: Aborted=${this.mAborted}, Done=${this.mDone}.`);
      return;
    }

    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Marking response as done.`);

    this.mDone = true;
    this.clear();

    if ( this.mDoneCallback ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Executing done callback.`);
      this.mDoneCallback(this);
    }
  }

  private clear(shouldAborted: boolean = false, error?: Error): void {
    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Clearing data reader, shouldAborted: ${shouldAborted}.`);

    if ( this.mDataReader ) {
      this.mDataReader.off('responseReady');
      this.mDataReader.off('newDataReadable');
      this.mDataReader.off('aborted');
      if ( shouldAborted ) this.mDataReader.abort(error);
      this.mDataReader = undefined;
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Data reader cleared.`);
    }
  }

  on(event: "dataReceive" | "aborted" | "done", callback: Function): void {
    switch (event) {
      case 'dataReceive':
        this.mDataReceiveCallback = callback as (response: IMCHttpResponse, data: string | ArrayBuffer) => void | Promise<void>;
        break;
      case 'aborted':
        this.mAbortedCallback = callback as (response: IMCHttpResponse, error?: Error) => void | Promise<void>;
        break;
      case 'done':
        this.mDoneCallback = callback as (response: IMCHttpResponse) => void | Promise<void>;
        break;
    }

    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' registered.`);
  }

  off(event: "dataReceive" | "aborted" | "done"): void {
    switch (event) {
      case 'dataReceive':
        this.mDataReceiveCallback = undefined;
        break;
      case 'aborted':
        this.mAbortedCallback = undefined;
        break;
      case 'done':
        this.mDoneCallback = undefined;
        break;
    }

    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' unregistered.`);
  }
}