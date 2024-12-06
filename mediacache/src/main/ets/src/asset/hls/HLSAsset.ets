import { IMCAsset } from "../../defines/IMCAsset";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCMedia } from "../../media/MCMedia";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import MCURL from "../../utils/MCURL";

export class HLSAsset extends MCReadwriteReference<HLSAsset> implements IMCAsset {
  /** HLS 会有多个媒体文件; */
  private mMedias: Map<string, IMCMedia> = new Map();
  private mDir: string;
  private mInitPlaylistPromise: Promise<IMCMedia> | undefined;
  private mInitPromises: Map<string, Promise<IMCMedia>> = new Map();

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

  async getMediaBy(requestTarget: string): Promise<IMCMedia> {
    const targetInfo = MCURL.parse(requestTarget);
    if ( targetInfo.assetId !== this.id ) {
      throw new Error(`xxx`);
    }

    const mediaId = targetInfo.mediaId;
    let media: IMCMedia | undefined = this.mMedias.get(mediaId);
    if ( media ) {
      return media.readwriteRetain();
    }

    if ( !targetInfo.isRoot ) {
      media = new MCMedia(mediaId, this.mDir);
      this.mMedias.set(mediaId, media);
      return media.readwriteRetain();
    }

    // 请求的是 playlist
    if ( !this.mInitPlaylistPromise ) {
      this.mInitPlaylistPromise = this.initializePlaylist(targetInfo);
    }
    media = await this.mInitPlaylistPromise;
    return media.readwriteRetain();
  }

  protected getInstance(): HLSAsset {
    return this;
  }

  /**
   * 请求 playlist 时的处理:
   * 1. 获取代理媒体
   *    1.1 如果不存在, 则下载并生成代理内容保存在本地
   * */
  private async initializePlaylist(targetInfo: MCURL.ProxyTargetInfo): Promise<IMCMedia> {

    throw new Error(``)
  }
}