import { socket } from '@kit.NetworkKit';
import { IMCHttpRequest } from '../defines/IMCHttpRequest';
import { IMCHttpResponse } from '../defines/IMCHttpResponse';
import { MCLogModule } from '../defines/MCLogModule';
import MCConfigs from '../utils/MCConfigs';
import MCLogger from '../utils/MCLogger';
import { parseRequest } from './MCHttpRequest';
import { MCHttpResponse } from './MCHttpResponse';
import { HashMap } from '@kit.ArkTS';

export interface IMCHttpConnectionHandler {
  handleConnection(cnt: socket.TCPSocketConnection): void;
}

interface IMCHttpConnectionResponseHandler {
  on(event: "disconnect", callback: (handler: IMCHttpConnectionResponseHandler) => void): void;
  off(event: "disconnect"): void;
}

export class MCHttpConnectionHandler implements IMCHttpConnectionHandler {
  // key: clientId
  private mResponseHandlers: HashMap<number, IMCHttpConnectionResponseHandler> = new HashMap();

  constructor() {
    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `Instance created.`);
  }

  handleConnection(cnt: socket.TCPSocketConnection): void {
    const clientId: number = cnt.clientId;
    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] New connection established.`);

    const responseHandler = new MCHttpConnectionResponseHandler(cnt);
    this.mResponseHandlers.set(clientId, responseHandler);
    responseHandler.on("disconnect", () => this.mResponseHandlers.remove(clientId));
  }
}

class MCHttpConnectionResponseHandler implements IMCHttpConnectionResponseHandler {
  private mClientId: number;
  private mConnection: socket.TCPSocketConnection;
  private mCurrentResponse?: IMCHttpResponse = undefined;
  private mDisconnected = false;
  private mSerialPromise = Promise.resolve();
  private mHeadersSent = false; // headers 是否已发送;
  private mConsuming = false;

  private mOnDisconnect?: (handler: IMCHttpConnectionResponseHandler) => void = undefined;

  constructor(cnt: socket.TCPSocketConnection) {
    this.mClientId = cnt.clientId;
    this.mConnection = cnt;
    cnt.on('message', (msgInfo: socket.SocketMessageInfo) => this.onConnectionMessage(msgInfo));
    cnt.on('error', (e: Error) => this.onError(e));
    cnt.on('close', () => this.onConnectionDisconnect());
  }

  on(_: "disconnect", callback: (handler: IMCHttpConnectionResponseHandler) => void): void {
    this.mOnDisconnect = callback;
  }

  off(_: "disconnect"): void {
    this.mOnDisconnect = undefined;
  }

  private onConnectionMessage(msgInfo: socket.SocketMessageInfo): void {
    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${this.mClientId}] New message received.`);

    // 取消之前的响应;
    this.abortResponse(new Error('Request is cancelled'));

    // 处理新消息
    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${this.mClientId}] Starting to parse incoming request`);
    let request: IMCHttpRequest;
    try {
      request = this.parseHttpRequest(msgInfo)
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${this.mClientId}] Parsed request: ${JSON.stringify(request)}`);
    }
    catch (error) {
      MCLogger.error(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${this.mClientId}] Error while parsing request: ${error.message}. Closing connection. Stack trace: ${error.stack}}`);

      // 解析请求失败, 发送错误请求的响应, 并主动关闭连接
      const rawData = "HTTP/1.1 400 Bad Request\r\n\r\n";
      this.enqueueTask(() => this.send(rawData));
      this.enqueueTask(() => this.close());
      this.enqueueTask(() => this.onConnectionDisconnect());
      return;
    }

    // 进行响应
    const response = new MCHttpResponse(this.mClientId, request);
    response.on("newDataReadable", (response) => this.onResponseNewDataReadable(response));
    response.on("aborted", (response, error) => this.onResponseAborted(response, error));
    this.mCurrentResponse = response;
    this.mHeadersSent = false;
    this.mConsuming = false;

    // prepare
    this.enqueueTask(() => response.prepare().then((rawHeaders) => this.onResponseHeaders(response, rawHeaders)));
  }

  /** 中止响应以及断开连接; */
  private onError(error: Error): void {
    MCLogger.error(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${this.mClientId}] On error: ${error.message}. Stack trace: ${error.stack}`);

    this.abortResponse(error);
    this.enqueueTask(() => this.close());
    this.enqueueTask(() => this.onConnectionDisconnect());
  }

  /** 连接已断开 */
  private onConnectionDisconnect(): void {
    if ( this.mDisconnected ) {
      return;
    }

    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${this.mClientId}] Connection disconnect`);

    this.mDisconnected = true;
    this.mConnection.off('message');
    this.mConnection.off('error');
    this.mConnection.off('close');
    this.mOnDisconnect?.(this);
  }

  /** 接收到响应 headers */
  private onResponseHeaders(response: IMCHttpResponse, headers: string): void {
    this.enqueueTask(async () => {
      if ( this.isActive(response) ) {
        this.mHeadersSent = true;
        await this.mConnection.send({ data: headers });
      }
    });

    this.enqueueTask(() => this.consumeData(response));
  }

  /** 有新数据可响应 */
  private onResponseNewDataReadable(response: IMCHttpResponse): void {
    if ( !this.isActive(response) || !this.mHeadersSent ) {
      return;
    }

    this.enqueueTask(() => this.consumeData(response));
  }

  /** 响应被中止 */
  private onResponseAborted(response: IMCHttpResponse, error: Error): void {
    response.off("newDataReadable");
    response.off("aborted");

    if ( this.isActive(response) ) {
      // header 消息已发送, 此时 response 是在读取过程中被中止了;
      if ( this.mHeadersSent ) {
        this.onError(error);
        return;
      }

      // headers 消息未发送, 此时 response 可能在 prepare 阶段内部出错就被中止了;
      this.mCurrentResponse = undefined;

      // 发送内部服务出错的响应, 并主动断开连接
      const rawData = "HTTP/1.1 500 Internal Server Error\r\n\r\n";
      this.enqueueTask(() => this.send(rawData));
      this.enqueueTask(() => this.close());
      this.enqueueTask(() => this.onConnectionDisconnect());
    }
  }

  /** 响应完毕 */
  private onResponseDone(response: IMCHttpResponse): void {
    // 响应完毕后, 清理当前的resp对象, 此时不需要主动关闭连接, 我们等待客户端继续请求或客户端主动关闭即可;
    response.off("newDataReadable");
    response.off("aborted");

    if ( this.isActive(response) ) {
      this.mCurrentResponse = undefined;
      this.mHeadersSent = false;
      this.mConsuming = false;
    }
  }

  private send(data: string | ArrayBuffer): Promise<void> {
    return this.mConnection.send({  data: data });
  }

  private close(): Promise<void> {
    return this.mConnection.close();
  }

  private isActive(response: IMCHttpResponse): boolean {
    return !this.mDisconnected && response == this.mCurrentResponse;
  }

  private consumeData(response: IMCHttpResponse): void {
    if ( this.mConsuming ) {
      return;
    }

    this.mConsuming = true;
    this.enqueueTask(async () => {
      if ( !this.isActive(response) ) {
        return;
      }

      const buffer = await response.read(MCConfigs.socketDataBufferSize);
      await this.mConnection.send({ data: buffer });
      if ( !response.isDone ) {
        setTimeout(() => {
          this.mConsuming = false;
          this.consumeData(response);
        }, 100); // 延迟后继续读取, 防止大数据读取递归调用频繁, 大量占用cpu的问题;
      }
      else {
        this.onResponseDone(response);
      }
    });
  }

  private abortResponse(error?: Error): void {
    const response = this.mCurrentResponse;
    if ( response ) {
      response.off("newDataReadable");
      response.off("aborted");
      this.mCurrentResponse = undefined;
      this.mHeadersSent = false;
      this.mConsuming = false;

      if ( !response.isCompleted ) {
        MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${this.mClientId}] Aborting current response`);
        response.abort(error);
      }
    }
  }

  // throw if error
  private parseHttpRequest(msgInfo: socket.SocketMessageInfo): IMCHttpRequest {
    let buffer: ArrayBuffer = msgInfo.message;
    let dataView = new DataView(buffer);
    let rawMessage = "";
    for (let i = 0; i < dataView.byteLength; ++i) {
      rawMessage += String.fromCharCode(dataView.getUint8(i));
    }
    return parseRequest(this.mClientId, rawMessage);
  }

  // 确保操作按顺序串行执行
  private enqueueTask(task: () => (void | Promise<void>)): void {
    this.mSerialPromise = this.mSerialPromise
      .catch((e: Error) => this.onError(e)) // 捕获上一个任务的异常，防止链断裂
      .then(async () => {
        if ( this.mDisconnected ) {
          return;
        }
        return task(); // 执行新任务
      });
  }
}