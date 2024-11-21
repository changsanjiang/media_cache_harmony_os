import { socket } from "@kit.NetworkKit";
import { IMCHttpRequest } from "../common/IMCHttpRequest";
import { IMCHttpResponse } from "../common/IMCHttpResponse";
import MCLogger from "../utils/MCLogger";
import { parseRequest } from "./MCHttpRequest";
import { MCHttpResponse } from "./MCHttpResponse";

export interface IMCHttpConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void;
}

export class MCHttpConnectionHandler implements IMCHttpConnectionHandler {
  constructor() {
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCHttpConnectionHandler] New HttpConnectionHandler instance created.`);
  }

  handleConnection(connection: socket.TCPSocketConnection): void {
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] New connection established.`);
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Creating response object.`);
    const response: IMCHttpResponse = new MCHttpResponse(connection.clientId);
    // 监听响应数据, 有可用数据时发送给客户端;
    response.on("newDataAvailable", async (response: IMCHttpResponse) => {
      try {
        while (true) {
          // 读取一段数据;
          const data = await response.readData();
          if (!data) {
            MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] No data available, waiting for next callback...`);
            // break, 等待下一段可用数据的回调;
            break;
          }
          // 发送数据;
          await connection.send({ data: data })
          MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Data sent, size: ${(typeof data === 'string') ? data.length : data.byteLength}`);

          // 所有数据都发送完毕后, 关闭连接;
          if ( await response.isDone ) {
            MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] All data sent, closing connection.`);
            this.clean(response, connection);
            break;
          }
        }
      }
      catch (e) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Error while sending data: ${(e as Error).message}. Closing connection.`);
        this.internalError(response, connection, true);
      }
    });

    response.on('aborted', async (response) => {
      this.internalError(response, connection);
    });

    // 监听客户端消息;
    connection.on('message', async (data: socket.SocketMessageInfo) => {
      let proxyRequest: IMCHttpRequest | undefined = undefined;
      try {
        let buffer: ArrayBuffer = data.message;
        let dataView = new DataView(buffer);
        let rawMessage = "";
        for (let i = 0; i < dataView.byteLength; ++i) {
          rawMessage += String.fromCharCode(dataView.getUint8(i));
        }
        MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Parsing request: ${rawMessage}`);
        // 解析代理请求;
        proxyRequest = parseRequest(connection.clientId, rawMessage)
        MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Request parsed successfully: ${JSON.stringify(proxyRequest)}`);
      }
      catch (e) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Error while parsing request: ${(e as Error).message}. Closing connection.`);
        this.badRequestError(response, connection, e);
      }

      if (proxyRequest) {
        try {
          // 准备响应
          MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Preparing response.`);
          await response.prepare(proxyRequest);
          MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Response prepared successfully.`);
        }
        catch (e) {
          MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Error while preparing response: ${(e as Error).message}. Closing connection.`);
          this.internalError(response, connection, e);
        }
      }
    });

    connection.on('error', async (e: Error) => {
      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Connection error: ${e.message}`);
      this.internalError(response, connection, true, e);
    });

    connection.on('close', async () => {
      MCLogger.log(MCLogger.LogLevel.WARN, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Connection closed.`);
      if ( !(await response.isAborted || await response.isDone) ) {
        response.off('newDataAvailable');
        response.off('aborted');
        response.abort(new Error("Connection closed unexpectedly."));
      }
    });
  }

  async internalError(response: IMCHttpResponse, connection: socket.TCPSocketConnection, shouldAborted: boolean = false, error?: Error) {
    if ( !(await response.isHeadersSent) ) connection.send({ data: "HTTP/1.1 500 Internal Server Error\r\n\r\n" });
    this.clean(response, connection, shouldAborted, error);
  }

  async badRequestError(response: IMCHttpResponse, connection: socket.TCPSocketConnection, error: Error) {
    await connection.send({ data: "HTTP/1.1 400 Bad Request\r\n\r\n" })
    this.clean(response, connection, true, error);
  }

  async clean(response: IMCHttpResponse, connection: socket.TCPSocketConnection, shouldAborted: boolean = false, error?: Error) {
    response.off('newDataAvailable');
    response.off('aborted');
    if ( shouldAborted && !(await response.isAborted || await response.isDone)) response.abort(error);
    connection.off('message');
    connection.off('error');
    connection.off('close');
    connection.close();
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler][clientId: ${connection.clientId}] Connection cleaned up, aborted: ${shouldAborted}`);
  }
}