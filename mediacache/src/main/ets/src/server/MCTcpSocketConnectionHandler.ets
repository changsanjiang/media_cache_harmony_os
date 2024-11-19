import { socket } from "@kit.NetworkKit";
import { parseHttpRequest } from "./MCHttpRequest";
import { MCHttpResponse } from "./MCHttpResponse";

export interface IMCTcpSocketConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void;
}

export class MCTcpSocketConnectionHandler implements IMCTcpSocketConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void {
    const response = new MCHttpResponse();
    // 监听响应数据, 有可用数据时发送给客户端;
    response.on("newDataAvailable", async (response) => {
      try {
        while (true) {
          // 读取一段数据;
          const data = await response.readData();
          if (!data) {
            // break, 等待下一段可用数据的回调;
            break;
          }
          // 发送数据;
          await connection.send({ data: data })

          // 所有数据都发送完毕后, 关闭连接;
          if ( await response.isDone ) {
            connection.off('message');
            connection.off('error');
            connection.off('close');
            connection.close();
            break;
          }
        }
      }
      catch (e) {
        console.log(`response.onNewDataAvailable error: ${(e as Error).message}`);
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
        // 解析请求;
        const request = parseHttpRequest(rawMessage);
        // 开始准备响应数据;
        await response.prepare(request);
      }
      catch (e) {
        console.log(`connection.onMessage error: ${(e as Error).message}`);
        response.abort();
        connection.close();
      }
    });

    connection.on('error', async (e) => {
      console.log(`connection.onError error: ${e.message}`);
      response.abort();
      connection.close();
    });

    connection.on('close', async () => {
      console.log(`connection.onClose()`);
      response.abort();
    });
  }
}