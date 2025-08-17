import { IMCAsset } from '../defines/IMCAsset';
import { IMCMedia } from '../defines/IMCMedia';
import { MCAssetType } from '../defines/MCAssetType';
import { MCReadwriteReference } from '../utils/MCReadwriteReference';

export class MCLocalHLSAsset extends MCReadwriteReference<MCLocalHLSAsset> implements IMCAsset {
  private mDir: string;

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;
  get type(): MCAssetType { return MCAssetType.HLS; }
  get isCached(): boolean { throw new Error("Method not implemented.") }
  get currentCachedSize(): number { throw new Error("Method not implemented.") };

  prepare(): Promise<void> {
    throw new Error("Method not implemented.");
  }

  getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    throw new Error("Method not implemented.");
  }

  protected getInstance(): MCLocalHLSAsset { throw new Error("Method not implemented."); }
  abort(error?: Error | undefined): Promise<void> { throw new Error("Method not implemented."); }
}