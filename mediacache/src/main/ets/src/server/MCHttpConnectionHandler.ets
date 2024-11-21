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
  handleConnection(connection: socket.TCPSocketConnection): void {
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler] New connection established with client ID: ${connection.clientId}`);

    const response: IMCHttpResponse = new MCHttpResponse();
    // 监听响应数据, 有可用数据时发送给客户端;
    response.on("newDataAvailable", async (response: IMCHttpResponse) => {
      try {
        while (true) {
          // 读取一段数据;
          const data = await response.readData();
          if (!data) {
            MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler] No data available for client ID: ${connection.clientId}, waiting for next callback...`);
            // break, 等待下一段可用数据的回调;
            break;
          }
          // 发送数据;
          await connection.send({ data: data })
          MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler] Data sent to client ID: ${connection.clientId}, size: ${(typeof data == 'string') ? data.length : data.byteLength}`);

          // 所有数据都发送完毕后, 关闭连接;
          if ( await response.isDone ) {
            MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler] All data sent to client ID: ${connection.clientId}. Closing connection.`);
            this.clean(response, connection);
            break;
          }
        }
      }
      catch (e) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler] Error while sending data to client ID: ${connection.clientId}: ${(e as Error).message}. Closing connection.`);
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
        MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler] Parsing request from client ID: ${connection.clientId}: ${rawMessage}`);
        // 解析代理请求;
        proxyRequest = parseRequest(rawMessage)
        MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler] Received request from client ID: ${connection.clientId}: ${JSON.stringify(proxyRequest)}`);
      }
      catch (e) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler] Error while processing message from client ID: ${connection.clientId}: ${(e as Error).message}. Closing connection.`);
        this.badRequestError(response, connection, e);
      }

      if (proxyRequest) {
        try {
          // 准备响应
          await response.prepare(proxyRequest);
          MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler] Preparing response for client ID: ${connection.clientId}`);
        }
        catch (e) {
          MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler] Error while preparing response from client ID: ${connection.clientId}: ${(e as Error).message}. Closing connection.`);
          this.internalError(response, connection, e);
        }
      }
    });

    connection.on('error', async (e: Error) => {
      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler] Connection error with client ID: ${connection.clientId}: ${e.message}`);
      this.internalError(response, connection, true, e);
    });

    connection.on('close', async () => {
      MCLogger.log(MCLogger.LogLevel.WARN, `[MCTcpSocketConnectionHandler] Connection closed for client ID: ${connection.clientId}`);
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
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler] Connection cleaned up for client ID: ${connection.clientId}, aborted: ${shouldAborted}`);
  }
}