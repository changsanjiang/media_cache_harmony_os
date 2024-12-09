import { MCUtils } from "../../../../../../Index";
import { IMCAsset } from "../../defines/IMCAsset";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCMedia } from "../../media/MCMedia";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import MCURL from "../../utils/MCURL";
import HLSParser from "./HLSParser";

export class HLSAsset extends MCReadwriteReference<HLSAsset> implements IMCAsset {
  /** HLS 会有多个媒体文件; */
  private mMedias: Map<string, IMCMedia> = new Map();
  private mDir: string;
  private mInitPromises: Map<string, Promise<IMCMedia>> = new Map();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;

  get isStored(): boolean {
    throw new Error("Method not implemented.");
  };

  get completeness(): Promise<number> {
    throw new Error("Method not implemented.");
  }

  prepare(): Promise<void> {
    throw new Error("Method not implemented.");
  }

  async getMediaBy(requestTarget: string): Promise<IMCMedia> {
    const targetInfo = MCURL.parse(requestTarget);
    if ( targetInfo.assetId !== this.id ) {
      throw new Error(`xxx`);
    }

    const mediaId = targetInfo.mediaId;
    let media: IMCMedia | undefined = this.mMedias.get(mediaId);
    if ( !media ) {
      if ( !this.mInitPromises.has(mediaId) ) {
        this.mInitPromises.set(mediaId, this.initializeMedia(targetInfo));
      }
      media = await this.mInitPromises.get(mediaId)!;
    }
    return media;
  }

  protected getInstance(): HLSAsset {
    return this;
  }

  private async initializeMedia(targetInfo: MCURL.ProxyTargetInfo): Promise<IMCMedia> {
    const mediaId = targetInfo.mediaId;
    let proxyHandler: ((requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer>) | undefined = undefined;
    if ( targetInfo.isRoot ) {
      proxyHandler = async (requestUrl, currentUrl, data) => {
        const playlist = MCUtils.bufferToString(data);
        // variantStreamSelectionHandler?: HLSDefines.VariantStreamSelectionHandler, renditionSelectionHandler?: HLSDefines.RenditionSelectionHandler
        const proxyPlaylist = await HLSParser.proxy(this.id, playlist, requestUrl, currentUrl);
        return MCUtils.stringToBuffer(proxyPlaylist);
      }
    }

    const media = new MCMedia(mediaId, this.mDir, proxyHandler);
    await media.prepare();
    this.mMedias.set(mediaId, media);
    return media;
  }
}