import { socket } from "@kit.NetworkKit";
import { ArkTSUtils } from "@kit.ArkTS";
import MCLogger from "../utils/MCLogger";
import { MCLogModule } from "../defines/MCLogModule";

/** media cache tcp socket server; */
export interface IMCTcpSocketServer {
  readonly isRunning: Promise<boolean>;
  readonly port: Promise<number>;
  /**
   * 启动本地 TCP 服务器监听连接请求; 启动成功后, 返回服务器监听的端口号.
   *
   * 1. 如果服务器未运行, 则绑定到本地 IP 地址 ("127.0.0.1") 并开始监听随机分配的端口.
   * 2. 一旦接收到连接请求, 则调用连接回调(如果已设置), 否则直接关闭连接.
   *
   * 注意事项：
   * - 该方法是线程安全的, 内部使用锁机制 (`mLock`) 确保启动过程不会被并发调用破坏.
   * - 如果启动失败, 会记录错误日志并将错误以 Promise 的形式抛出.
   */
  start(): Promise<number>;
  //on(event: 'isRunning', callback: () => void): Promise<void>;
  on(event: 'connect', callback: (connection: socket.TCPSocketConnection) => void): Promise<void>;
  off(_: 'connect'): Promise<void>;
}

export class MCTcpSocketServer implements IMCTcpSocketServer {
  private mTcpServer: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
  private mRunning = false
  private mPort = 0
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mConnectionCallback?: (connection: socket.TCPSocketConnection) => void = undefined;

  constructor() {
    MCLogger.info(MCLogModule.MCTcpSocketServer, () => `New Server instance created.`);
  }

  get isRunning(): Promise<boolean> { return this.mLock.lockAsync(() => this.mRunning); }
  get port(): Promise<number> { return this.mLock.lockAsync(() => this.mPort); }

  start(): Promise<number> {
    MCLogger.debug(MCLogModule.MCTcpSocketServer, () => `Start Server; Checking server state...`);
    return this.mLock.lockAsync(async () => {
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
        return Promise.reject(e);
      }
    })
  }

  // stop(): Promise<void> {
  //   return this.mLock.lockAsync(async () => {
  //     if ( this.mRunning ) {
  //       this.mTcpServer.off("connect");
  //       this.mRunning = false;
  //     }
  //   });
  // }

  // on(_: "isRunning", callback: () => void): Promise<void> {
  //   throw new Error("Method not implemented.");
  // }

  on(event: 'connect', callback: (connection: socket.TCPSocketConnection) => void): Promise<void> {
    return this.mLock.lockAsync(() => {
      this.mConnectionCallback = callback;
      MCLogger.debug(MCLogModule.MCTcpSocketServer, () => `Event listener for '${event}' registered;`);
    });
  }

  off(event: 'connect'): Promise<void> {
    return this.mLock.lockAsync(() => {
      this.mConnectionCallback = undefined;
      MCLogger.debug(MCLogModule.MCTcpSocketServer, () => `Event listener for '${event}' unregistered;`);
    });
  }
}
