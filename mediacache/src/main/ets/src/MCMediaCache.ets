import MCAssetPrefetcher from "./prefetcher/MCAssetPrefetcher";
import { MCHttpConnectionHandler } from "./server/MCHttpConnectionHandler";
import { MCTcpSocketServer } from "./server/MCTcpSocketServer";

namespace MCMediaCache {
  const mTcpServer = new MCTcpSocketServer();
  const mConnectionHandler = new MCHttpConnectionHandler();

  export function startServer(): Promise<number> {
    mTcpServer.on('connect', (connection) => mConnectionHandler.handleConnection(connection));
    return mTcpServer.start();
  }

  export function getPort(): number {
    return mTcpServer.port;
  }

  export function prefetch(resUrl: string) {
    MCAssetPrefetcher.prefetch(resUrl, {
      prefetchFileCount: 2,
      onProgress: (progress) => {
        console.log(`[Progress] ${progress}`)
      }
    }).then(() => {
      console.log(`[Success] Prefetch success!`);
    }).catch((error: Error) => {
      console.log(`[Error] ${error.message}, Stack trace: ${error.stack}`);
    });
  }

  let mPreparationPromise: Promise<void>;

  class Init {
    constructor() {

    }
  }
  const mInit = new Init();
}

export default MCMediaCache;