import { socket } from "@kit.NetworkKit";
import { IMCHttpKeepAlive, parseKeepAlive } from "../defines/IMCHttpKeepAlive";
import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCHttpResponse } from "../defines/IMCHttpResponse";
import { MCLogModule } from "../defines/MCLogModule";
import MCLogger from "../utils/MCLogger";
import { parseRequest } from "./MCHttpRequest";
import { MCHttpResponse } from "./MCHttpResponse";

export interface IMCHttpConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void;
}

export class MCHttpConnectionHandler implements IMCHttpConnectionHandler {
  private mResponseMap: Map<number, MCHttpResponse> = new Map();

  constructor() {
    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => ` New HttpConnectionHandler instance created.`);
  }

  handleConnection(connection: socket.TCPSocketConnection): void {
    const clientId: number = connection.clientId;
    let isClosed = false; // 连接释放已断开;
    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] New connection established.`);

    connection.on('message', async (data: socket.SocketMessageInfo) => {
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] New message received.`);
      this.abortResponseBy(clientId, new Error(`Request cancelled`)); // 取消之前的响应

      let request: IMCHttpRequest | undefined = undefined;
      try {
        request = this.parseHttpRequest(clientId, data)
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Error while parsing request: ${(error as Error).message}. Closing connection.`);
        await connection.send({ data: "HTTP/1.1 400 Bad Request\r\n\r\n" });
        connection.close();
      }

      if ( !request ) {
        return;
      }

      const response = new MCHttpResponse(clientId, request);
      let isHeadersSent = false; // headers 是否已发送;
      this.mResponseMap.set(clientId, response);
      response.on('headersReceive', async (response: IMCHttpResponse, headers: string) => {
        if ( this.mResponseMap.get(clientId) === response && !isClosed ) {
          await connection.send({ data: headers });
          isHeadersSent = true;
          MCLogger.debug(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Headers sent: \n${headers}`);
        }
      });
      response.on('dataReceive', async (response: IMCHttpResponse, data: ArrayBuffer) => {
        if ( this.mResponseMap.get(clientId) === response && !isClosed ) {
          await connection.send({ data: data });
          MCLogger.debug(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Data sent, size: ${data.byteLength}`);
        }
      });
      response.on('aborted', async (response: IMCHttpResponse, _?: Error) => {
        this.clearResponseEvents(response);
        if ( this.mResponseMap.get(clientId) === response ) {
          this.mResponseMap.delete(clientId);
          if ( !isHeadersSent && !isClosed ) await connection.send({ data: "HTTP/1.1 500 Internal Server Error\r\n\r\n" });
          this.cancelTimeoutBy(connection.clientId);
          this.closeOrKeepConnection(request!, connection);
        }
      });
      response.on('dataEnd', (response: IMCHttpResponse) => {
        this.clearResponseEvents(response);
        if ( this.mResponseMap.get(clientId) === response ) {
          this.mResponseMap.delete(clientId);
          this.cancelTimeoutBy(connection.clientId);
          this.closeOrKeepConnection(request!, connection);
        }
      });
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Preparing response.`);
      response.prepare();
    });

    connection.on('error', (e: Error) => {
      isClosed = true;
      this.clearConnectionEvents(connection);
      this.cancelTimeoutBy(connection.clientId);
      const response = this.mResponseMap.get(clientId);
      if ( response ) {
        this.mResponseMap.delete(clientId);
        response.abort(e);
      }
      connection.close();
    });

    connection.on('close', () => {
      isClosed = true;
      this.clearConnectionEvents(connection);
      this.cancelTimeoutBy(connection.clientId);
      const response = this.mResponseMap.get(clientId);
      if ( response ) {
        this.mResponseMap.delete(clientId);
        response.abort(new Error("Connection closed unexpectedly."));
      }
    });
  }

  private mTimeoutIdMap: Map<number, number> = new Map(); // key: clientId, value: timeoutId;

  private closeOrKeepConnection(request: IMCHttpRequest, connection: socket.TCPSocketConnection) {
    if ( request.headers[`connection`] === `keep-alive` ) {
      const keepAliveHeader = request.headers[`keep-alive:`];
      const keepAlive: IMCHttpKeepAlive = keepAliveHeader ? parseKeepAlive(keepAliveHeader, 10, -1) : { timeout: 10, max: -1 };
      //  max param will be ignored;
      const shouldKeepAlive = keepAlive.timeout > 0;

      if ( shouldKeepAlive ) {
        const timeoutID = setTimeout(() => {
          this.mTimeoutIdMap.delete(connection.clientId);
          connection.close();
        }, keepAlive.timeout * 1000);
        this.mTimeoutIdMap.set(connection.clientId, timeoutID);
      }
    }
    else {
      connection.close();
    }
  }

  private cancelTimeoutBy(clientId: number) {
    const timeoutId = this.mTimeoutIdMap.get(clientId);
    if ( timeoutId ) {
      this.mTimeoutIdMap.delete(timeoutId);
      clearTimeout(timeoutId);
    }
  }

  private abortResponseBy(clientId: number, error?: Error) {
    const response = this.mResponseMap.get(clientId);
    if ( response ) {
      this.clearResponseEvents(response);
      this.mResponseMap.delete(clientId);
      response.abort(error);
    }
  }

  private clearResponseEvents(response: IMCHttpResponse) {
    response.off('headersReceive');
    response.off('dataReceive');
    response.off('dataEnd');
    response.off('aborted');
  }

  private clearConnectionEvents(connection: socket.TCPSocketConnection) {
    connection.off('message');
    connection.off('error');
    connection.off('close');
  }

  private parseHttpRequest(clientId: number, data: socket.SocketMessageInfo): IMCHttpRequest { // throw if error
    let buffer: ArrayBuffer = data.message;
    let dataView = new DataView(buffer);
    let rawMessage = "";
    for (let i = 0; i < dataView.byteLength; ++i) {
      rawMessage += String.fromCharCode(dataView.getUint8(i));
    }
    return parseRequest(clientId, rawMessage);
  }
}