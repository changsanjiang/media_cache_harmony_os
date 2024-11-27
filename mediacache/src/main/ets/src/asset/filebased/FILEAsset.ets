import { IMCAsset } from "../../defines/IMCAsset";
import { IMCAssetReader } from "../../defines/IMCAssetReader";
import { IMCHttpRequest } from "../../defines/IMCHttpRequest";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCDataDecryptHandler } from "../../defines/MCDataDecryptHandler";
import { MCMedia } from "../../media/MCMedia";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import MCRoot from "../../utils/MCRoot";

export class FILEAsset extends MCReadwriteReference<FILEAsset> implements IMCAsset {
  /** 基于文件的资产只有一个媒体; */
  private mMedia: IMCMedia;

  constructor(id: string) {
    super();
    this.id = id;
    this.mMedia = new MCMedia(id, MCRoot.assetDir(id));
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

  async createReaderBy(clientId: number, request: IMCHttpRequest, decrypt?: MCDataDecryptHandler): Promise<IMCAssetReader> {
    // TODO: 创建 AssetReader;
    throw new Error(``);
  }

  protected getInstance(): FILEAsset {
    return this;
  }
}