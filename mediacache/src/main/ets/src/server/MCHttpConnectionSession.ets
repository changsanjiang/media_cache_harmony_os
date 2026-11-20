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
  on(event: "disconnect", callback: (session: IMCHttpConnectionSession) => void): void;
  off(event: "disconnect"): void;
}

/** 单条 TCP 连接上的 HTTP 请求/响应状态机。 */
export class MCHttpConnectionSession implements IMCHttpConnectionSession {
  private mClientId: number;
  private mConnection: socket.TCPSocketConnection;
  private mCurrentResponse?: IMCHttpResponse = undefined;
  private mDisconnected = false;
  private mIoSerialChain = Promise.resolve();
  private mHeadersSent = false;
  private mBodyPumpActive = false;
  private mReceiveBuffer: MCHttpReceiveBuffer;

  private mOnDisconnect?: (session: IMCHttpConnectionSession) => void = undefined;

  constructor(connection: socket.TCPSocketConnection) {
    this.mClientId = connection.clientId;
    this.mConnection = connection;
    this.mReceiveBuffer = new MCHttpReceiveBuffer(this.mClientId);
    connection.on('message', (msgInfo: socket.SocketMessageInfo) => this.handleTcpMessage(msgInfo));
    connection.on('error', (e: Error) => this.onSocketError(e));
    connection.on('close', () => this.handleDisconnect());

    MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'Session initialized'));
  }

  on(_: "disconnect", callback: (session: IMCHttpConnectionSession) => void): void {
    this.mOnDisconnect = callback;
  }

  off(_: "disconnect"): void {
    this.mOnDisconnect = undefined;
  }

  private handleTcpMessage(msgInfo: socket.SocketMessageInfo): void {
    MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `TCP segment ${msgInfo.message.byteLength} bytes`));

    try {
      this.mReceiveBuffer.append(msgInfo.message);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Receive buffer error: ${(error as Error).message}. Closing connection.`));
      this.closeWithErrorStatus(400);
      return;
    }

    while (true) {
      const headerText = this.mReceiveBuffer.takeCompleteRequestHeaders();
      if (!headerText) {
        break;
      }

      this.cancelCurrentResponse(new Error('Request is cancelled'));

      let request: IMCHttpRequest;
      try {
        request = parseRequest(this.mClientId, headerText);
        MCLogger.info(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Request ${MCHttpLog.summarizeRequest(request)}`));
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Parse failed: ${(error as Error).message}`));
        this.closeWithErrorStatus(400);
        return;
      }

      this.dispatchRequest(request);
    }
  }

  private closeWithErrorStatus(statusCode: 400 | 500): void {
    const rawData = MCHttpWireFormat.formatErrorResponse(statusCode);
    this.enqueueIoTask(() => this.sendOnSocket(rawData));
    this.enqueueIoTask(() => this.closeSocket());
    this.enqueueIoTask(() => this.handleDisconnect());
  }

  private dispatchRequest(request: IMCHttpRequest): void {
    const response = new MCHttpResponseAdapter(this.mClientId, request);
    response.on("newDataReadable", (response) => this.onResponseNewDataReadable(response));
    response.on("aborted", (response, error) => this.onResponseAborted(response, error));
    this.mCurrentResponse = response;
    this.mHeadersSent = false;
    this.mBodyPumpActive = false;

    this.enqueueIoTask(() => response.prepare().then((rawHeaders) => this.onResponseHeaders(response, rawHeaders)));
  }

  private onSocketError(error: Error): void {
    MCLogger.error(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Connection error: ${error.message}`));

    this.cancelCurrentResponse(error);
    this.enqueueIoTask(() => this.closeSocket());
    this.enqueueIoTask(() => this.handleDisconnect());
  }

  private handleDisconnect(): void {
    if ( this.mDisconnected ) {
      return;
    }

    MCLogger.info(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'TCP connection closed'));

    this.cancelCurrentResponse(new Error('Request is cancelled'));
    this.mDisconnected = true;
    this.mConnection.off('message');
    this.mConnection.off('error');
    this.mConnection.off('close');
    this.mOnDisconnect?.(this);
  }

  private onResponseHeaders(response: IMCHttpResponse, headers: string): void {
    this.enqueueIoTask(async () => {
      if ( this.isCurrentResponse(response) ) {
        this.mHeadersSent = true;
        MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Sending response headers (${headers.length} chars)`));
        await this.mConnection.send({ data: headers });

        if ( response.isDone ) {
          this.onResponseDone(response);
        }
      }
    });

    if ( !response.omitsResponseBody ) {
      this.enqueueIoTask(() => this.pumpResponseBody(response));
    }
  }

  private onResponseNewDataReadable(response: IMCHttpResponse): void {
    MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'newDataReadable'));

    if ( !this.isCurrentResponse(response) || !this.mHeadersSent ) {
      return;
    }

    this.enqueueIoTask(() => this.pumpResponseBody(response));
  }

  private onResponseAborted(response: IMCHttpResponse, error: Error): void {
    response.off("newDataReadable");
    response.off("aborted");

    if ( this.isCurrentResponse(response) ) {
      MCLogger.warn(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Response aborted (headersSent=${this.mHeadersSent}): ${error.message}`));

      if ( this.mHeadersSent ) {
        this.onSocketError(error);
        return;
      }

      this.mCurrentResponse = undefined;
      this.closeWithErrorStatus(500);
    }
  }

  private onResponseDone(response: IMCHttpResponse): void {
    response.off("newDataReadable");
    response.off("aborted");

    if ( this.isCurrentResponse(response) ) {
      this.mCurrentResponse = undefined;
      this.mHeadersSent = false;
      this.mBodyPumpActive = false;
      MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'Response finished'));
    }
  }

  private sendOnSocket(data: string | ArrayBuffer): Promise<void> {
    return this.mConnection.send({ data: data });
  }

  private closeSocket(): Promise<void> {
    return this.mConnection.close();
  }

  private isCurrentResponse(response: IMCHttpResponse): boolean {
    return !this.mDisconnected && response == this.mCurrentResponse;
  }

  private pumpResponseBody(response: IMCHttpResponse): void {
    if (this.mBodyPumpActive) {
      MCLogger.trace(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'pumpResponseBody re-entry skipped'));
      return;
    }

    this.mBodyPumpActive = true;

    this.enqueueIoTask(async () => {
      if ( !this.isCurrentResponse(response) ) {
        MCLogger.debug(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, 'pumpResponseBody skipped (stale response)'));
        return;
      }

      try {
        const buffer = await response.read(MCConfigs.socketDataBufferSize);
        if ( !buffer ) {
          this.mBodyPumpActive = false;
          return;
        }

        MCLogger.trace(MCLogModule.MCHttpConnectionSession, () => MCLogger.withClient(this.mClientId, `Wrote body ${buffer.byteLength} bytes`));
        await this.mConnection.send({ data: buffer });

        if ( response.isDone ) {
          this.onResponseDone(response);
          this.mBodyPumpActive = false;
          return;
        }

        this.scheduleBodyPump(response);
      }
      catch (e) {
        this.mBodyPumpActive = false;
        this.onSocketError(e as Error);
      }
    });
  }

  private scheduleBodyPump(response: IMCHttpResponse): void {
    setTimeout(() => {
      if ( this.isCurrentResponse(response) ) this.resumeBodyPump(response);
    });
  }

  private resumeBodyPump(response: IMCHttpResponse): void {
    this.mBodyPumpActive = false;
    this.pumpResponseBody(response);
  }

  private cancelCurrentResponse(error: Error): void {
    const response = this.mCurrentResponse;
    if ( response ) {
      const abortMsg = () => MCLogger.withClient(this.mClientId, `Cancel response: ${error.message}`);
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
      this.mBodyPumpActive = false;

      if ( !response.isCompleted ) {
        response.abort(error);
      }
    }
  }

  private enqueueIoTask(task: () => (void | Promise<void>)): void {
    this.mIoSerialChain = this.mIoSerialChain
      .then(async () => {
        if ( this.mDisconnected ) {
          return;
        }
        return task();
      })
      .catch((e: Error) => this.onSocketError(e));
  }
}