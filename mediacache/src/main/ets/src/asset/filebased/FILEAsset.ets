import { IMCAsset } from "../../defines/IMCAsset";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCAssetType } from "../../defines/MCAssetType";
import { MCMediaKind } from "../../defines/MCMediaKind";
import { MCMedia } from "../../media/MCMedia";
import { MCAbortController, MCAbortSignal } from "../../utils/MCAbortController";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import MCAssetCacheManager from "../cachemgr/MCAssetCacheManager";

export class FILEAsset extends MCReadwriteReference<FILEAsset> implements IMCAsset {
  /** 基于文件的资产只有一个媒体; 所以 FILEAsset 只需要管理这一个 Media 即可; */
  private mMedia: IMCMedia;
  // private mDir: string;
  private mAbortController = new MCAbortController();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    // this.mDir = dir;
    this.mMedia = new MCMedia(id, MCMediaKind.FILE, dir, this.mAbortController.signal);
  }

  readonly id: string;

  get type(): MCAssetType {
    return MCAssetType.FILE_BASED;
  }

  get isCached(): boolean {
    return this.mMedia.isAssembled;
  }

  get currentCachedSize(): number {
    return this.mMedia.currentCachedSize;
  }

  prepare(): Promise<void> {
    return this.mMedia.prepare();
  }

  async getMediaBy(_: string): Promise<IMCMedia> {
    if ( this.mAbortController.signal.isAborted ) {
      throw this.mAbortController.signal.reason!;
    }
    return this.mMedia;
  }

  protected getInstance(): FILEAsset {
    return this;
  }

  readwriteRetain(): FILEAsset {
    super.readwriteRetain();
    MCAssetCacheManager.onAssetReadwrite(this);
    return this;
  }

  abort(error?: Error): Promise<void> {
    return this.mAbortController.abort(error);
  }
}