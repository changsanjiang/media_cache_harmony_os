import { socket } from "@kit.NetworkKit";
import { ArkTSUtils } from "@kit.ArkTS";
import MCLogger from "../utils/MCLogger";

/** media cache tcp socket server; */
export interface IMCTcpSocketServer {
  readonly isRunning: Promise<boolean>;
  readonly port: Promise<number>;
  /**
   * 启动本地 TCP 服务器并监听连接请求。
   *
   * 1. 如果服务器未运行，绑定到本地 IP 地址 ("127.0.0.1") 并开始监听随机分配的端口。
   * 2. 一旦接收到连接请求，调用用户提供的连接回调（如果已定义），否则直接关闭连接。
   * 3. 服务器成功启动后，返回分配的端口号。
   *
   * 注意事项：
   * - 该方法是线程安全的，内部使用锁机制 (`mLock`) 确保启动过程不会被并发调用破坏。
   * - 如果启动失败，会记录错误日志并将错误以 Promise 的形式抛出。
   *
   * 返回值：
   * - 一个 Promise，解析后返回服务器监听的端口号。
   */
  start(): Promise<number>;
  //on(event: 'isRunning', callback: () => void): Promise<void>;
  on(event: 'connect', callback: (connection: socket.TCPSocketConnection) => void): Promise<void>;
  off(_: 'connect'): Promise<void>;
}

export class MCTcpSocketServer implements IMCTcpSocketServer {
  private mTcpServer = socket.constructTCPSocketServerInstance();
  private mRunning = false
  private mPort = 0
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mConnectionCallback?: (connection: socket.TCPSocketConnection) => void = undefined;

  get isRunning(): Promise<boolean> { return this.mLock.lockAsync(() => this.mRunning); }
  get port(): Promise<number> { return this.mLock.lockAsync(() => this.mPort); }

  start(): Promise<number> {
    MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketServer] start() invoked; Checking server state...`);
    return this.mLock.lockAsync(async () => {
      try {
        if ( !this.mRunning ) {
          const ipAddress: socket.NetAddress = {
            address: "127.0.0.1"
          };
          MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketServer] Server not running, initializing with address ${ipAddress.address}...`);
          await this.mTcpServer.listen(ipAddress);
          MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketServer] Server successfully bound to ${ipAddress.address}, waiting for connections...`);
          this.mTcpServer.on("connect", (connection) => {
            MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketServer] New connection received ${connection.clientId}.`);
            this.mConnectionCallback ? this.mConnectionCallback?.(connection) : connection.close();
          });
          this.mPort = (await this.mTcpServer.getLocalAddress()).port as number;
          this.mRunning = true;
          MCLogger.log(MCLogger.LogLevel.INFO, `[MCTcpSocketServer] Server is now running on port ${this.mPort}.`);
        }
        else {
          MCLogger.log(MCLogger.LogLevel.WARN, `[MCTcpSocketServer] Attempted to start server, but it is already running on port ${this.mPort}.`);
        }
        return this.mPort;
      }
      catch (e) {
        MCLogger.log(MCLogger.LogLevel.ERROR, `[MCTcpSocketServer] Failed to start server due to error: ${(e as Error).message}`);
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

  on(_: 'connect', callback: (connection: socket.TCPSocketConnection) => void): Promise<void> {
    MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketServer] on(connect) invoked;`);
    return this.mLock.lockAsync(() => { this.mConnectionCallback = callback } );
  }

  off(_: 'connect'): Promise<void> {
    MCLogger.log(MCLogger.LogLevel.DEBUG, `[MCTcpSocketServer] off(connect) invoked;`);
    return this.mLock.lockAsync(() => { this.mConnectionCallback = undefined } );
  }
}
