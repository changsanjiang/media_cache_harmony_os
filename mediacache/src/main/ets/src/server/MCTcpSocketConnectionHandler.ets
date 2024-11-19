import { socket } from "@kit.NetworkKit";
import { parseHttpRequest } from "./MCHttpRequest";
import { MCHttpResponse } from "./MCHttpResponse";

export interface IMCTcpSocketConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void;
}

export class MCTcpSocketConnectionHandler implements IMCTcpSocketConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void {
    const response = new MCHttpResponse();
    response.on("newDataAvailable", async (response) => {
      try {
        while (true) {
          const data = await response.readData();
          if ( !data ) {
            break;
          }
          await connection.send({ data: data })
        }
      }
      catch (e) {
        // TODO: handle e;
      }
    });

    connection.on('message', (data) => {
      try {
        let buffer = data.message;
        let dataView = new DataView(buffer);
        let rawMessage = "";
        for (let i = 0; i < dataView.byteLength; ++i) {
          rawMessage += String.fromCharCode(dataView.getUint8(i));
        }
        const request = parseHttpRequest(rawMessage);
        response.prepare(request);
      }
      catch (e) {
        // TODO: handle e;
      }
    });

    connection.on('error', (err) => {
      // TODO: handle e;
    });

    connection.on('close', () => {
      // TODO: handle close;
    });
  }
}