import { socket } from '@kit.NetworkKit';
import { IMCHttpRequest } from '../defines/IMCHttpRequest';
import { IMCHttpResponse } from '../defines/IMCHttpResponse';
import { MCLogModule } from '../defines/MCLogModule';
import MCConfigs from '../utils/MCConfigs';
import MCLogger from '../utils/MCLogger';
import { parseRequest } from './MCHttpRequest';
import { MCHttpResponseAdapter } from './MCHttpResponseAdapter';
import { MCHttpReceiveBuffer } from './MCHttpReceiveBuffer';
import { MCHttpWireFormat } from './MCHttpWireFormat';
import { MCHttpLog } from './MCHttpLog';

export interface IMCHttpConnectionSession {
  on(event: "disconnect", callback: (handler: IMCHttpConnectionSession) => void): void;
  off(event: "disconnect"): void;
}

/** 单条 TCP 连接上的 HTTP 请求/响应状态机。 */
export class MCHttpConnectionSession implements IMCHttpConnectionSession {
  private mClientId: number;
  private mConnection: socket.TCPSocketConnection;
  private mCurrentResponse?: IMCHttpResponse = undefined;
  private mDisconnected = false;
  private mSerialPromise = Promise.resolve();
  private mHeadersSent = false;
  private mConsuming = false;
  private mReceiveBuffer: MCHttpReceiveBuffer;

  private mOnDisconnect?: (handler: IMCHttpConnectionSession) => void = undefined;

  constructor(cnt: socket.TCPSocketConnection) {
    this.mClientId = cnt.clientId;
    this.mConnection = cnt;
    this.mReceiveBuffer = new MCHttpReceiveBuffer(this.mClientId);
    cnt.on('message', (msgInfo: socket.SocketMessageInfo) => this.onConnectionMessage(msgInfo));
    cnt.on('error', (e: Error) => this.onError(e));
    cnt.on('close', () => this.onConnectionDisconnect());

    MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'Session initialized'));
  }

  on(_: "disconnect", callback: (handler: IMCHttpConnectionSession) => void): void {
    this.mOnDisconnect = callback;
  }

  off(_: "disconnect"): void {
    this.mOnDisconnect = undefined;
  }

  private onConnectionMessage(msgInfo: socket.SocketMessageInfo): void {
    MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `TCP segment ${msgInfo.message.byteLength} bytes`));

    try {
      this.mReceiveBuffer.append(msgInfo.message);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Receive buffer error: ${(error as Error).message}. Closing connection.`));
      this.closeWithError(400);
      return;
    }

    while (true) {
      const headerBlock = this.mReceiveBuffer.tryShiftCompleteHeaderBlock();
      if (!headerBlock) {
        break;
      }

      this.abortResponse(new Error('Request is cancelled'));

      let request: IMCHttpRequest;
      try {
        request = parseRequest(this.mClientId, headerBlock);
        MCLogger.info(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Request ${MCHttpLog.summarizeRequest(request)}`));
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Parse failed: ${(error as Error).message}`));
        this.closeWithError(400);
        return;
      }

      this.startResponse(request);
    }
  }

  private closeWithError(statusCode: 400 | 500): void {
    const rawData = MCHttpWireFormat.formatErrorResponse(statusCode);
    this.enqueueTask(() => this.send(rawData));
    this.enqueueTask(() => this.close());
    this.enqueueTask(() => this.onConnectionDisconnect());
  }

  private startResponse(request: IMCHttpRequest): void {
    const response = new MCHttpResponseAdapter(this.mClientId, request);
    response.on("newDataReadable", (response) => this.onResponseNewDataReadable(response));
    response.on("aborted", (response, error) => this.onResponseAborted(response, error));
    this.mCurrentResponse = response;
    this.mHeadersSent = false;
    this.mConsuming = false;

    this.enqueueTask(() => response.prepare().then((rawHeaders) => this.onResponseHeaders(response, rawHeaders)));
  }

  private onError(error: Error): void {
    MCLogger.error(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Connection error: ${error.message}`));

    this.abortResponse(error);
    this.enqueueTask(() => this.close());
    this.enqueueTask(() => this.onConnectionDisconnect());
  }

  private onConnectionDisconnect(): void {
    if ( this.mDisconnected ) {
      return;
    }

    MCLogger.info(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'TCP connection closed'));

    this.abortResponse(new Error('Request is cancelled'));
    this.mDisconnected = true;
    this.mConnection.off('message');
    this.mConnection.off('error');
    this.mConnection.off('close');
    this.mOnDisconnect?.(this);
  }

  private onResponseHeaders(response: IMCHttpResponse, headers: string): void {
    this.enqueueTask(async () => {
      if ( this.isActive(response) ) {
        this.mHeadersSent = true;
        MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Sending response headers (${headers.length} chars)`));
        await this.mConnection.send({ data: headers });

        if ( response.isDone ) {
          this.onResponseDone(response);
        }
      }
    });

    if ( !response.omitsResponseBody ) {
      this.enqueueTask(() => this.consumeData(response));
    }
  }

  private onResponseNewDataReadable(response: IMCHttpResponse): void {
    MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'newDataReadable'));

    if ( !this.isActive(response) || !this.mHeadersSent ) {
      return;
    }

    this.enqueueTask(() => this.consumeData(response));
  }

  private onResponseAborted(response: IMCHttpResponse, error: Error): void {
    response.off("newDataReadable");
    response.off("aborted");

    if ( this.isActive(response) ) {
      MCLogger.warn(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Response aborted (headersSent=${this.mHeadersSent}): ${error.message}`));

      if ( this.mHeadersSent ) {
        this.onError(error);
        return;
      }

      this.mCurrentResponse = undefined;
      this.closeWithError(500);
    }
  }

  private onResponseDone(response: IMCHttpResponse): void {
    response.off("newDataReadable");
    response.off("aborted");

    if ( this.isActive(response) ) {
      this.mCurrentResponse = undefined;
      this.mHeadersSent = false;
      this.mConsuming = false;
      MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'Response finished'));
    }
  }

  private send(data: string | ArrayBuffer): Promise<void> {
    return this.mConnection.send({ data: data });
  }

  private close(): Promise<void> {
    return this.mConnection.close();
  }

  private isActive(response: IMCHttpResponse): boolean {
    return !this.mDisconnected && response == this.mCurrentResponse;
  }

  private consumeData(response: IMCHttpResponse): void {
    if (this.mConsuming) {
      MCLogger.trace(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'consumeData re-entry skipped'));
      return;
    }

    this.mConsuming = true;

    this.enqueueTask(async () => {
      if ( !this.isActive(response) ) {
        MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'consumeData skipped (inactive response)'));
        return;
      }

      try {
        const buffer = await response.read(MCConfigs.socketDataBufferSize);
        if ( !buffer ) {
          this.mConsuming = false;
          return;
        }

        MCLogger.trace(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Wrote body ${buffer.byteLength} bytes`));
        await this.mConnection.send({ data: buffer });

        if ( response.isDone ) {
          this.onResponseDone(response);
          this.mConsuming = false;
          return;
        }

        this.scheduleNextConsume(response);
      }
      catch (e) {
        this.mConsuming = false;
        this.onError(e as Error);
      }
    });
  }

  private scheduleNextConsume(response: IMCHttpResponse): void {
    setTimeout(() => {
      if ( this.isActive(response) ) this.forceConsumeData(response);
    });
  }

  private forceConsumeData(response: IMCHttpResponse): void {
    this.mConsuming = false;
    this.consumeData(response);
  }

  private abortResponse(error: Error): void {
    const response = this.mCurrentResponse;
    if ( response ) {
      const abortMsg = () => MCLogger.withClient(this.mClientId, `Abort response: ${error.message}`);
      if (error.message === 'Request is cancelled') {
        MCLogger.debug(MCLogModule.MCHttpConnectionSession, abortMsg);
      }
      else {
        MCLogger.info(MCLogModule.MCHttpConnectionSession, abortMsg);
      }

      response.off("newDataReadable");
      response.off("aborted");
      this.mCurrentResponse = undefined;
      this.mHeadersSent = false;
      this.mConsuming = false;

      if ( !response.isCompleted ) {
        response.abort(error);
      }
    }
  }

  private enqueueTask(task: () => (void | Promise<void>)): void {
    this.mSerialPromise = this.mSerialPromise
      .then(async () => {
        if ( this.mDisconnected ) {
          return;
        }
        return task();
      })
      .catch((e: Error) => this.onError(e));
  }
}