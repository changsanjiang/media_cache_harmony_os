import { IMCAsset } from "../defines/IMCAsset";
import { IMCMedia } from "../defines/IMCMedia";
import { MCAssetType } from "../defines/MCAssetType";
import { MCMediaKind } from "../defines/MCMediaKind";
import { MCMedia } from "../media/MCMedia";
import { MCAbortController } from "../utils/MCAbortController";
import { MCReadwriteReference } from "../utils/MCReadwriteReference";

export class MCLocalFILEAsset extends MCReadwriteReference<MCLocalFILEAsset> implements IMCAsset {
  private mMedia: IMCMedia;
  private mAbortController = new MCAbortController();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mMedia = new MCMedia(id, MCMediaKind.FILE, dir, this.mAbortController.signal);
  }

  readonly id: string;
  get type(): MCAssetType {
    return MCAssetType.FILE_BASED;
  }
  get isCached(): boolean {
    return true;
  }
  get currentCachedSize(): number {
    return 0;
  }

  prepare(): Promise<void> {
    return this.mMedia.prepare();
  }

  async getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    if ( this.mAbortController.signal.isAborted ) {
      throw this.mAbortController.signal.reason!;
    }
    return this.mMedia;
  }

  protected getInstance(): MCLocalFILEAsset {
    return this;
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mAbortController.abort(error);
  }
}