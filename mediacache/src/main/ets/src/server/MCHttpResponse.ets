import MCLogger from "../utils/MCLogger";
import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCHttpResponse } from "../defines/IMCHttpResponse";
import { MCLogModule } from "../defines/MCLogModule";
import { MCAssetDataFetcher } from "../asset/MCAssetDataFetcher";
import { IMCDataFetcher } from "../defines/IMCDataFetcher";
import MCAssetManager from "../asset/MCAssetManager";

export class MCHttpResponse implements IMCHttpResponse {
  private mClientId: number;
  private mRequest: IMCHttpRequest
  private mFetcher?: IMCDataFetcher = undefined;
  private mHeadersReceiveCallback?: (response: IMCHttpResponse, headers: string) => void | Promise<void> = undefined;
  private mDataReceiveCallback?: (response: IMCHttpResponse, data: ArrayBuffer) => void | Promise<void> = undefined;
  private mAbortedCallback?: (response: IMCHttpResponse, error?: Error) => void | Promise<void> = undefined;
  private mDataEndCallback?: (response: IMCHttpResponse) => void | Promise<void> = undefined;
  private mAborted = false;
  private mDataEnd = false;

  constructor(clientId: number, request: IMCHttpRequest) {
    this.mClientId = clientId;
    this.mRequest = request;
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${clientId}] Instance created for request: ${JSON.stringify(request)}.`);
  }

  async prepare(): Promise<void> {
    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing response for request: ${JSON.stringify(this.mRequest)}`);
    try {
      const asset = await MCAssetManager.getAssetBy(this.mRequest.requestTarget);
      this.mFetcher = new MCAssetDataFetcher(this.mClientId, asset, {
        requestTarget: this.mRequest.requestTarget,
        headers: this.mRequest.headers
      });
      this.mFetcher.on('responseReceive', async (_, responseHeaders: string) => this.onResponseReceive(responseHeaders));
      this.mFetcher.on('dataReceive', (_, offset, data: ArrayBuffer) => this.onDataReceive(offset, data));
      this.mFetcher.on('dataEnd', (_) => this.onDataEnd());
      this.mFetcher.on('aborted', (_, error) => this.onError(error));
      this.mFetcher.prepare();
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Error during asset reader preparation: ${error.message}`);
      this.onError(error);
      throw error as Error;
    }
  }

  private async onResponseReceive(responseHeaders: string): Promise<void> {
    if ( this.mAborted ) {
      return;
    }

    try {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing to send response headers.`);
      await this.mHeadersReceiveCallback?.(this, responseHeaders);
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Response headers have been sent successfully. Headers is below: \n${responseHeaders}`);
    }
    catch (error) {
      this.onError(error);
      throw error as Error;
    }
  }

  private async onDataReceive(_: number, data: ArrayBuffer): Promise<void> {
    if ( this.mAborted ) {
      return;
    }
    try {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Preparing to send response body data.`);
      await this.mDataReceiveCallback?.(this, data);
      MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Sent data successfully: ${data.byteLength} bytes.`);
    }
    catch (error) {
      this.onError(error);
      throw error as Error;
    }
  }

  private onDataEnd(): void {
    if ( this.mAborted || this.mDataEnd ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Done ignored: Aborted=${this.mAborted}, Done=${this.mDataEnd}.`);
      return;
    }

    MCLogger.info(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Marking response as done.`);

    this.mDataEnd = true;
    this.clear();

    if ( this.mDataEndCallback ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Executing dataEnd callback.`);
      this.mDataEndCallback(this);
    }
  }

  private onError(error?: Error): void {
    if ( !this.mAborted ) {
      this.abort(error);
    }
    else {
      this.clear(error);
    }
  }

  async abort(error?: Error | undefined): Promise<void> {
    if ( this.mAborted || this.mDataEnd ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Abort ignored: Aborted=${this.mAborted}, Done=${this.mDataEnd}.`);
      return;
    }

    MCLogger.warn(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Aborting MCHttpResponse${error ? ` due to error: ${error.message}` : ''}`);

    this.mAborted = true;

    await this.clear(error);

    if ( this.mAbortedCallback ) {
      MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Executing aborted callback with error: ${error?.message || 'None'}.`);
      this.mAbortedCallback(this, error);
    }
  }

  private async clear(error?: Error): Promise<void> {
    if ( this.mFetcher ) {
      this.mFetcher.off('responseReceive');
      this.mFetcher.off('dataReceive');
      this.mFetcher.off('dataEnd');
      this.mFetcher.off('aborted');
      try { await this.mFetcher.abort(error); } catch (_) { }
      this.mFetcher = undefined;
    }
  }

  on(event: "headersReceive" | "dataReceive" | "dataEnd" | "aborted", callback: Function): void {
    switch (event) {
      case 'headersReceive':
        this.mHeadersReceiveCallback = callback as (response: IMCHttpResponse, headers: string) => void | Promise<void>;
        break;
      case 'dataReceive':
        this.mDataReceiveCallback = callback as (response: IMCHttpResponse, data: ArrayBuffer) => void | Promise<void>;
        break;
      case 'dataEnd':
        this.mDataEndCallback = callback as (response: IMCHttpResponse) => void | Promise<void>;
        break;
      case 'aborted':
        this.mAbortedCallback = callback as (response: IMCHttpResponse, error?: Error) => void | Promise<void>;
        break;
    }

    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' registered.`);
  }

  off(event: "headersReceive" | "dataReceive" | "dataEnd" | "aborted"): void {
    switch (event) {
      case 'headersReceive':
        this.mHeadersReceiveCallback = undefined;
        break;
      case 'dataReceive':
        this.mDataReceiveCallback = undefined;
        break;
      case 'dataEnd':
        this.mDataEndCallback = undefined;
        break;
      case 'aborted':
        this.mAbortedCallback = undefined;
        break;
    }

    MCLogger.debug(MCLogModule.MCHttpResponse, () => `[clientId: ${this.mClientId}] Event listener for '${event}' unregistered.`);
  }
}