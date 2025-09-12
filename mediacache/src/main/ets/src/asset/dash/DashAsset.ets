import { IMCAsset } from "../../defines/IMCAsset";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCAssetType } from "../../defines/MCAssetType";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";

export class DashAsset extends MCReadwriteReference<DashAsset> implements IMCAsset {
  private mDir: string;

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;
  type: MCAssetType = MCAssetType.DASH;
  isCached: boolean = false;
  currentCachedSize: number = 0;

  prepare(): Promise<void> {
    throw new Error("Method not implemented.");
  }

  getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    throw new Error("Method not implemented.");
  }

  abort(error?: Error | undefined): Promise<void> {
    throw new Error("Method not implemented.");
  }

}