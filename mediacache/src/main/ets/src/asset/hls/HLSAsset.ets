import { IMCAsset } from "../../defines/IMCAsset";
import { IMCDataReader } from "../../defines/IMCDataReader";
import { IMCDataRequest } from "../../defines/IMCDataRequest";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCDataDecryptHandler } from "../../defines/MCDataDecryptHandler";
import { MCMedia } from "../../media/MCMedia";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";

export class HLSAsset extends MCReadwriteReference<HLSAsset> implements IMCAsset {
  private mMedias: Map<string, MCMedia> = new Map();
  private mDir: string;

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;

  get isStored(): Promise<boolean> {
    throw new Error("Method not implemented.");
  };

  get completeness(): Promise<number> {
    throw new Error("Method not implemented.");
  }

  prepare(): Promise<void> {
    throw new Error("Method not implemented.");
  }

  createReaderBy(clientId: number, request: IMCDataRequest, decrypt?: MCDataDecryptHandler): Promise<IMCDataReader> {
    throw new Error("Method not implemented.");
  }

  getMediaBy(requestTarget: string): Promise<IMCMedia> {
    throw new Error("Method not implemented.");
  }

  protected getInstance(): HLSAsset {
    return this;
  }
}