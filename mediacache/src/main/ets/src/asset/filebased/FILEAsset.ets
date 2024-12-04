import { IMCAsset } from "../../defines/IMCAsset";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCMedia } from "../../media/MCMedia";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";

export class FILEAsset extends MCReadwriteReference<FILEAsset> implements IMCAsset {
  /** 基于文件的资产只有一个媒体; */
  private mMedia: IMCMedia;
  private mDir: string;

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
    this.mMedia = new MCMedia(id, dir);
  }

  readonly id: string;

  get isStored(): Promise<boolean> {
    return this.mMedia.isStored;
  };

  get completeness(): Promise<number> {
    return this.mMedia.completeness;
  }

  prepare(): Promise<void> {
    return this.mMedia.prepare();
  }

  async getMediaBy(_: string): Promise<IMCMedia> {  // media readwrite retained, should release after;
    return this.mMedia.readwriteRetain('FILE_ASSET');
  }

  protected getInstance(): FILEAsset {
    return this;
  }
}