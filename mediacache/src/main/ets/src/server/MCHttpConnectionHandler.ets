import { socket } from "@kit.NetworkKit";
import { IMCHttpKeepAlive, parseKeepAlive } from "../defines/IMCHttpKeepAlive";
import { IMCHttpRequest } from "../defines/IMCHttpRequest";
import { IMCHttpResponse } from "../defines/IMCHttpResponse";
import { MCLogModule } from "../defines/MCLogModule";
import MCConfigs from "../utils/MCConfigs";
import MCLogger from "../utils/MCLogger";
import { parseRequest } from "./MCHttpRequest";
import { MCHttpResponse } from "./MCHttpResponse";

export interface IMCHttpConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void;
}

export class MCHttpConnectionHandler implements IMCHttpConnectionHandler {
  private mResponseMap: Map<number, MCHttpResponse> = new Map();

  constructor() {
    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `Instance created.`);
  }

  handleConnection(connection: socket.TCPSocketConnection): void {
    const clientId: number = connection.clientId;
    let isClosed = false; // 连接是否已断开;
    MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] New connection established.`);
    connection.on('message', async (data: socket.SocketMessageInfo) => {
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] New message received.`);

      this.abortResponseBy(clientId, new Error(`Request is cancelled.`)); // 取消之前的响应

      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Starting to parse incoming request.`);
      let request: IMCHttpRequest | undefined = undefined;
      try {
        request = this.parseHttpRequest(clientId, data)
        MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Parsed request: ${JSON.stringify(request)}`);
      }
      catch (error) {
        MCLogger.error(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Error while parsing request: ${(error as Error).message}. Closing connection.`);
        try { await this.sendWithTimeout(connection, "HTTP/1.1 400 Bad Request\r\n\r\n"); } catch (_) { }
        connection.close();
      }

      if ( !request ) {
        MCLogger.error(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] No valid request parsed. Connection will be closed.`);
        connection.close();
        return;
      }

      const response = new MCHttpResponse(clientId, request);
      let isHeadersSent = false; // headers 是否已发送;
      this.mResponseMap.set(clientId, response);

      response.on('headersReceive', async (response: IMCHttpResponse, headers: string) => {
        const isActive = this.mResponseMap.get(clientId) === response && !isClosed;
        MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Headers received. isActive: ${isActive}.`);
        if ( isActive ) {
          try {
            await this.sendWithTimeout(connection, headers);
            isHeadersSent = true;
            MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Headers sent: \n${headers}`);
          }
          catch (error) {
            MCLogger.error(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Error sending Headers: ${error.message}`);
            isClosed = true;
            this.closeConnection(connection, 'Send headers failed');
            return;
          }
        }
      });

      response.on('dataReceive', async (response: IMCHttpResponse, data: ArrayBuffer) => {
        const isActive = this.mResponseMap.get(clientId) === response && !isClosed;
        MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Data received. isActive: ${isActive}.`);
        if ( isActive ) {
          try {
            await this.sendWithTimeout(connection, data);
            MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Data sent, size: ${data.byteLength}`);
          }
          catch (error) {
            MCLogger.error(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Error sending data: ${error.message}`);
            isClosed = true;
            this.closeConnection(connection, 'Send data failed');
            return;
          }
        }
      });
      response.on('aborted', async (response: IMCHttpResponse, _?: Error) => {
        MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Response aborted.`);

        this.clearResponseEvents(response);
        if ( this.mResponseMap.get(clientId) === response ) {
          this.mResponseMap.delete(clientId);
          if ( !isHeadersSent && !isClosed ) await connection.send({ data: "HTTP/1.1 500 Internal Server Error\r\n\r\n" });
          this.cancelTimeoutBy(connection.clientId);
          this.closeOrKeepConnection(request!, connection);
        }
      });
      response.on('dataEnd', (response: IMCHttpResponse) => {
        MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Data end reached.`);

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
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Connection error callback: ${e.message}.`);

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
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Connection closed callback.`);

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

  // 发送数据超时控制
  private async sendWithTimeout(connection: socket.TCPSocketConnection, data: string | ArrayBuffer, timeoutMs: number = MCConfigs.socketDataSendTimeoutInterval): Promise<void> {
    if ( timeoutMs === 0 ) {
      return connection.send({ data: data });
    }

    return new Promise((resolve, reject) => {
      const timeoutId = setTimeout(() => {
        this.closeConnection(connection, 'Send data timed out');
        reject(new Error('Send data timed out.'));
      }, timeoutMs);

      connection.send({ data }).then(() => {
        clearTimeout(timeoutId);
        resolve();
      }).catch((err: Error) => {
        clearTimeout(timeoutId);
        reject(err);
      });
    });
  }

  private mTimeoutIdMap: Map<number, number> = new Map(); // key: clientId, value: timeoutId;

  private closeOrKeepConnection(request: IMCHttpRequest, connection: socket.TCPSocketConnection) {
    if ( request.headers[`connection`].toLowerCase() === `keep-alive` ) {
      const keepAliveHeader = request.headers[`keep-alive`];
      const keepAlive: IMCHttpKeepAlive = keepAliveHeader ? parseKeepAlive(keepAliveHeader, 10, -1) : { timeout: 10, max: -1 };
      //  max param will be ignored;
      const shouldKeepAlive = keepAlive.timeout > 0;

      if ( shouldKeepAlive ) {
        MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${connection.clientId}] Keeping connection alive, closing after ${keepAlive.timeout}s.`);

        const timeoutID = setTimeout(() => {
          MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${connection.clientId}] Timeout reached, closing connection after ${keepAlive.timeout}s.`);
          this.mTimeoutIdMap.delete(connection.clientId);
          this.closeConnection(connection, 'timeout');
        }, keepAlive.timeout * 1000);
        this.mTimeoutIdMap.set(connection.clientId, timeoutID);
      }
    }
    else {
      this.closeConnection(connection, 'immediately');
    }
  }

  private async closeConnection(connection: socket.TCPSocketConnection, reason: string): Promise<void> {
    try {
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${connection.clientId}] Closing connection with reason: ${reason}.`);
      await connection.close();
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${connection.clientId}] Connection closed successfully.`);
    } catch (err) {
      MCLogger.error(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${connection.clientId}] Error closing connection: ${(err as Error).message}`);
    }
  }

  private cancelTimeoutBy(clientId: number) {
    const timeoutId = this.mTimeoutIdMap.get(clientId);
    if ( timeoutId !== undefined ) {
      clearTimeout(timeoutId);
      this.mTimeoutIdMap.delete(timeoutId);
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Timeout cancelled.`);
    }
  }

  private abortResponseBy(clientId: number, error?: Error) {
    const response = this.mResponseMap.get(clientId);
    if ( response ) {
      MCLogger.info(MCLogModule.MCHttpConnectionHandler, () => `[clientId: ${clientId}] Aborting response.`);

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