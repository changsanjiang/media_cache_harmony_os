import { IMCAsset } from "../defines/IMCAsset";
import { IMCMedia } from "../defines/IMCMedia";
import { MCAssetType } from "../defines/MCAssetType";
import { MCMediaKind } from "../defines/MCMediaKind";
import { MCMedia } from "../media/MCMedia";
import { MCAbortController } from "../utils/MCAbortController";
import { MCReadwriteReference } from "../utils/MCReadwriteReference";

export class MCLocalFILEAsset extends MCReadwriteReference<MCLocalFILEAsset> implements IMCAsset {
  private mDir: string;
  private mMedia: IMCMedia | undefined = undefined;
  private mAbortController = new MCAbortController();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
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

  async prepare(): Promise<void> {
    // 在指定目录加载媒体元数据
    // 如果元数据文件不存在或数据异常(被篡改/损坏)异常则返回undefined;
    // const metadata = await MCMediaMetadataManager.loadMetadata(this.id, this.mDir);
    // if ( !metadata ) {
    //   throw new Error(`xxx`);
    // }



    return Promise.resolve();
  }

  async getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    // if ( this.mAbortController.signal.isAborted ) {
    //   throw this.mAbortController.signal.reason!;
    // }
    // return this.mMedia;
    throw new Error(``);
  }

  protected getInstance(): MCLocalFILEAsset {
    return this;
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mAbortController.abort(error);
  }
}