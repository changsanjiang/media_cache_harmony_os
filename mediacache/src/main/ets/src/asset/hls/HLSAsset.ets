import { IMCAsset } from "../../defines/IMCAsset";
import { IMCDataReader } from "../../defines/IMCDataReader";
import { IMCHttpRequest } from "../../defines/IMCHttpRequest";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCDataDecryptHandler } from "../../defines/MCDataDecryptHandler";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";

export class HLSAsset extends MCReadwriteReference<HLSAsset> implements IMCAsset {
  constructor(id: string) {
    super();
    this.id = id;
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

  createReaderBy(clientId: number, request: IMCHttpRequest, decrypt?: MCDataDecryptHandler | undefined): Promise<IMCDataReader> {
    throw new Error("Method not implemented.");
  }

  getMediaBy(requestTarget: string): Promise<IMCMedia> {
    throw new Error("Method not implemented.");
  }

  protected getInstance(): HLSAsset {
    return this;
  }
}