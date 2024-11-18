import { socket } from "@kit.NetworkKit";
import { ArkTSUtils } from "@kit.ArkTS";

/** media cache tcp socket server; */
export interface IMCTcpSocketServer {
  readonly isRunning: Promise<boolean>;
  readonly port: Promise<number>;

  /** 启动本地服务器; */
  start(): Promise<boolean>;
  //on(event: 'isRunning', callback: () => void): Promise<void>;
  on(event: 'connect', callback: (connection: socket.TCPSocketConnection) => void): void;
  off(_: 'connect'): void;
}

export class MCTcpSocketServer implements IMCTcpSocketServer {
  private mTcpServer = socket.constructTCPSocketServerInstance();
  private mRunning = false
  private mPort = 0
  private mLock: ArkTSUtils.locks.AsyncLock = new ArkTSUtils.locks.AsyncLock();
  private mConnectionCallback?: (connection: socket.TCPSocketConnection) => void = undefined;

  get isRunning(): Promise<boolean> { return this.mLock.lockAsync(() => this.mRunning); }
  get port(): Promise<number> { return this.mLock.lockAsync(() => this.mPort); }

  start(): Promise<boolean> {
    return this.mLock.lockAsync(async () => {
      if ( !this.mRunning ) {
        const ipAddress: socket.NetAddress = {
          address: "127.0.0.1"
        };
        await this.mTcpServer.listen(ipAddress);
        this.mTcpServer.on("connect", (connection) => this.mConnectionCallback ? this.mConnectionCallback?.(connection) : connection.close());
        this.mPort = (await this.mTcpServer.getLocalAddress()).port as number;
        this.mRunning = true;
      }
      return this.mRunning;
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

  on(_: 'connect', callback: (connection: socket.TCPSocketConnection) => void): void {
    this.mLock.lockAsync(() => this.mConnectionCallback = callback );
  }

  off(_: 'connect'): void {
    this.mLock.lockAsync(() => this.mConnectionCallback = undefined );
  }
}
