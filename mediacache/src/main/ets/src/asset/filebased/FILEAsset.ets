import { IMCAsset } from "../../defines/IMCAsset";
import { IMCDataReader } from "../../defines/IMCDataReader";
import { IMCDataRequest } from "../../defines/IMCDataRequest";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCDataDecryptHandler } from "../../defines/MCDataDecryptHandler";
import { MCMedia } from "../../media/MCMedia";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import MCRoot from "../../utils/MCRoot";
import { FILEAssetReader } from "./FILEAssetReader";

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

  async createReaderBy(clientId: number, request: IMCDataRequest, decrypt?: MCDataDecryptHandler): Promise<IMCDataReader> {
    const reader = new FILEAssetReader(await this.readwriteRetain(), clientId, request, decrypt);
    return reader;
  }

  getMediaBy(_: string): Promise<IMCMedia> {
    return this.mMedia.readwriteRetain();
  }

  protected getInstance(): FILEAsset {
    return this;
  }
}