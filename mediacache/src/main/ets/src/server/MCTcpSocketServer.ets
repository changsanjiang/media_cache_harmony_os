import { socket } from "@kit.NetworkKit";
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";

/** media cache tcp socket server; */
export interface IMCTcpSocketServer {
  readonly isRunning: boolean;
  readonly port: number;
  /**  启动本地 TCP 服务器监听连接请求; 启动成功后, 返回服务器监听的端口号. */
  start(): Promise<number>;

  on(event: 'connect', callback: (connection: socket.TCPSocketConnection) => void): void;
  off(_: 'connect'): void;
}

export class MCTcpSocketServer implements IMCTcpSocketServer {
  private mTcpServer: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
  private mRunning = false
  private mPort = 0
  private mConnectionCallback?: (connection: socket.TCPSocketConnection) => void = undefined;

  constructor() {
    MCLogger.info(MCLogModule.MCTcpSocketServer, () => `New Server instance created.`);
  }

  get isRunning(): boolean { return this.mRunning; }
  get port(): number { return this.mPort; }

  async start(): Promise<number> {
    MCLogger.debug(MCLogModule.MCTcpSocketServer, () => `Start Server; Checking server state...`);
    try {
      if ( !this.mRunning ) {
        const ipAddress: socket.NetAddress = {
          address: "127.0.0.1"
        };
        MCLogger.debug(MCLogModule.MCTcpSocketServer, () => `Server not running, initializing with address ${ipAddress.address}...`);
        await this.mTcpServer.listen(ipAddress);
        MCLogger.info(MCLogModule.MCTcpSocketServer, () => `Server successfully bound to ${ipAddress.address}, waiting for connections...`);
        this.mTcpServer.on("connect", (connection: socket.TCPSocketConnection) => {
          MCLogger.info(MCLogModule.MCTcpSocketServer, () => `New connection received with client ID: ${connection.clientId}.`);
          this.mConnectionCallback ? this.mConnectionCallback?.(connection) : connection.close();
        });
        this.mPort = (await this.mTcpServer.getLocalAddress()).port as number;
        this.mRunning = true;
        MCLogger.info(MCLogModule.MCTcpSocketServer, () => `Server is now running on port ${this.mPort}.`);
      }
      else {
        MCLogger.warn(MCLogModule.MCTcpSocketServer, () => `Attempted to start server, but it is already running on port ${this.mPort}.`);
      }
      return this.mPort;
    }
    catch (e) {
      MCLogger.error(MCLogModule.MCTcpSocketServer, () => `Failed to start server due to error: ${(e as Error).message}`);
      throw e as Error;
    }
  }

  on(event: 'connect', callback: (connection: socket.TCPSocketConnection) => void): void {
    this.mConnectionCallback = callback;
    MCLogger.debug(MCLogModule.MCTcpSocketServer, () => `Event listener for '${event}' registered;`);
  }

  off(event: 'connect'): void {
    this.mConnectionCallback = undefined;
    MCLogger.debug(MCLogModule.MCTcpSocketServer, () => `Event listener for '${event}' unregistered;`);
  }
}
