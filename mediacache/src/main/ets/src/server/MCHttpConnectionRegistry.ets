import { socket } from '@kit.NetworkKit';
import { MCLogModule } from '../defines/MCLogModule';
import MCLogger from '../utils/MCLogger';
import { HashMap } from '@kit.ArkTS';
import { IMCHttpConnectionSession, MCHttpConnectionSession } from './MCHttpConnectionSession';

export interface IMCHttpConnectionRegistry {
  handleConnection(cnt: socket.TCPSocketConnection): void;
}

/** 活动 TCP 连接注册表：为每条连接创建 {@link MCHttpConnectionSession}。 */
export class MCHttpConnectionRegistry implements IMCHttpConnectionRegistry {
  private mSessions: HashMap<number, IMCHttpConnectionSession> = new HashMap();

  constructor() {
    MCLogger.debug(MCLogModule.MCHttpConnectionRegistry, () => 'Registry created');
  }

  handleConnection(cnt: socket.TCPSocketConnection): void {
    const clientId: number = cnt.clientId;
    MCLogger.info(MCLogModule.MCHttpConnectionRegistry, () => MCLogger.withClient(clientId, 'TCP connection accepted'));

    const session = new MCHttpConnectionSession(cnt);
    this.mSessions.set(clientId, session);

    session.on("disconnect", () => {
      MCLogger.debug(MCLogModule.MCHttpConnectionRegistry, () => MCLogger.withClient(clientId, 'Session removed from registry'));
      this.mSessions.remove(clientId);
    });
  }
}