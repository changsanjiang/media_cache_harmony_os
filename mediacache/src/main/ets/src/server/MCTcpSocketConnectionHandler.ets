import { socket } from "@kit.NetworkKit";
import { IMCHttpResponse } from "../common/IMCHttpResponse";
import MCLogger from "../utils/MCLogger";
import { parseRequest } from "./MCHttpRequest";
import { MCHttpResponse } from "./MCHttpResponse";

export interface IMCTcpSocketConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void;
}

export class MCTcpSocketConnectionHandler implements IMCTcpSocketConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void {
    MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler] New connection established with client ID: ${connection.clientId}`);

    const response = new MCHttpResponse();
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
            connection.off('message');
            connection.off('error');
            connection.off('close');
            connection.close();
            response.off('newDataAvailable');
            response.off('aborted');
            break;
          }
        }
      }
      catch (e) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler] Error while sending data to client ID: ${(e as Error).message}. Closing connection.`);
        // TODO: make error response and clear events;
        response.abort();
        connection.close();
      }
    });

    // 监听客户端消息;
    connection.on('message', async (data) => {
      try {
        let buffer = data.message;
        let dataView = new DataView(buffer);
        let rawMessage = "";
        for (let i = 0; i < dataView.byteLength; ++i) {
          rawMessage += String.fromCharCode(dataView.getUint8(i));
        }
        // 解析代理请求;
        const proxyRequest = parseRequest(rawMessage);
        MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketConnectionHandler] Received request from client ID: ${connection.clientId}: ${JSON.stringify(proxyRequest)}`);
        // 准备响应;
        await response.prepare(proxyRequest);
        MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketConnectionHandler] Preparing response for client ID: ${connection.clientId}`);
      }
      catch (e) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler] Error while processing message from client ID: ${connection.clientId}: ${(e as Error).message}. Closing connection.`);
        // TODO: make error response and clear events;
        response.abort();
        connection.close();
      }
    });

    connection.on('error', async (e) => {
      MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketConnectionHandler] Connection error with client ID: ${connection.clientId}: ${e.message}`);
      // TODO: make error response and clear events;
      response.abort();
      connection.close();
    });

    connection.on('close', async () => {
      MCLogger.log(MCLogger.LogLevel.WARN, `[MCTcpSocketConnectionHandler] Connection closed for client ID: ${connection.clientId}`);
      response.abort();
    });
  }
}