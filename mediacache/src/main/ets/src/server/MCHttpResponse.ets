import { IMCDataReader } from "../defines/IMCDataReader";
import MCLogger from "../utils/MCLogger";
import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCHttpResponse } from "../defines/IMCHttpResponse";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAssetReader } from "../asset/MCAssetReader";

export class MCHttpResponse implements IMCHttpResponse {
  private mClientId: number;
  /// headers是否已发送给客户端;
  private mHeadersSent = false;
  private mDataReader?: IMCDataReader = undefined;
  private mNewDataCallback?: (response: IMCHttpResponse) => void = undefined;
  private mAbortedCallback?: (response: IMCHttpResponse, error?: Error) => void = undefined;
  private mAborted = false;
  private mDone = false;

  constructor(clientId: number) {
    this.mClientId = clientId;
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] New MCHttpResponse instance created.`);
  }

  get isDone(): boolean {
    return this.mDone;
  }

  get isAborted(): boolean {
    return this.mAborted;
  }

  get isHeadersSent(): boolean {
    return this.mHeadersSent;
  }

  async prepare(proxyRequest: IMCHttpRequest): Promise<void> {
    try {
      if (this.mDataReader) {
        throw new Error("A request is already being processed.");
      }

      if ( this.mDone || this.mAborted ) {
        console.log(`fdasfsdafsdafsdafsd`);
      }

      this.mDone = false;
      this.mAborted = false;
      this.mHeadersSent = false;

      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing data reader for request: ${JSON.stringify(proxyRequest)}`);

      this.mDataReader = new MCAssetReader(this.mClientId, {
        requestTarget: proxyRequest.requestTarget,
        headers: proxyRequest.headers
      });
      this.mDataReader.on('responseReady', (_) => this.mNewDataCallback?.(this));
      this.mDataReader.on('newDataReadable', (_) => this.mNewDataCallback?.(this));
      this.mDataReader.on('aborted', (_, error) => this.abort(error));
      this.mDataReader.on('done', (_) => this.done());
      await this.mDataReader.prepare();
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Data reader prepared successfully.`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Failed to prepare data reader: ${error.message}`);
      this.abort(error as Error);
      throw error as Error;
    }
  }

  async readData(): Promise<string | ArrayBuffer | undefined> {
    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Starting read data operation.`);

    try {
      if ( this.mDone || this.mAborted ) {
        MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Attempt to read data after response completion or abortion.`);
        return undefined;
      }

      const reader = this.mDataReader;
      if ( !reader ) {
        MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] No data reader found while attempting to read data.`);
        return undefined;
      }

      // 先向客户端发送响应头消息
      if ( !this.mHeadersSent ) {
        MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Generating response headers for data response.`);
        const responseHeaders = reader.responseHeaders;
        if ( responseHeaders ) {
          this.mHeadersSent = true;
          MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Response headers sent to client: \n${responseHeaders}`);
        }
        return responseHeaders;
      }

      // 读取数据
      const buffer = await reader.readData();
      if ( buffer ) {
        MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Data chunk read (${buffer?.byteLength} bytes).`);
        return buffer;
      }

      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] No data available for reading.`);
      return undefined;
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Error during data read: ${error.message}`);
      this.abort(error as Error);
      throw error as Error;
    }
  }

  async abort(error?: Error): Promise<void> {
    if ( this.mAborted || this.mDone ) {
      return;
    }

    MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Aborting MCHttpResponse${error ? ` due to error: ${error.message}` : ""}.`);

    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Marking response as aborted.`);

    this.mAborted = true;

    this.clear(true, error);

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || "None"}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private done(): void {
    if ( this.mAborted || this.mDone ) {
      return;
    }

    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Marking response as done.`);

    this.mDone = true;
    this.clear();
  }

  private clear(shouldAborted: boolean = false, error?: Error): void {
    MCLogger.debug(MCLogModule.MCMediaContentLoader, () => `Clearing data reader" ${this.mDataReader}, shouldAborted: ${shouldAborted}.`);

    if ( this.mDataReader ) {
      this.mDataReader.off('responseReady');
      this.mDataReader.off('newDataReadable');
      this.mDataReader.off('aborted');
      if ( shouldAborted ) this.mDataReader.abort(error);
      this.mDataReader = undefined;
    }
  }

  on(event: 'newDataAvailable' | 'aborted', callback: Object): void {
    switch (event) {
      case 'newDataAvailable': {
        if (this.mNewDataCallback) MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for 'newDataAvailable' is already registered.`);
        this.mNewDataCallback = callback as (reader: IMCHttpResponse) => void;
      }
        break;
      case 'aborted': {
        if (this.mAbortedCallback) MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' is being replaced.`);
        this.mAbortedCallback = callback as (reader: IMCHttpResponse, error?: Error) => void;
      }
        break;
    }
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' registered.`);
  }

  off(event: 'newDataAvailable' | 'aborted'): void {
    switch (event) {
      case 'newDataAvailable': {
        this.mNewDataCallback = undefined;
      }
        break;
      case 'aborted': {
        this.mAbortedCallback = undefined;
      }
        break;
    }
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' unregistered.`);
  }
}