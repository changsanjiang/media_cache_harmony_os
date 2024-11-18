import { socket } from "@kit.NetworkKit";

export interface IMCTcpSocketConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void;
}

export class MCTcpSocketConnectionHandler implements IMCTcpSocketConnectionHandler {
  handleConnection(connection: socket.TCPSocketConnection): void {
    connection.on('message', (data) => {

    });

    connection.on('error', (err) => {

    });

    connection.on('close', () => {

    });
  }
}