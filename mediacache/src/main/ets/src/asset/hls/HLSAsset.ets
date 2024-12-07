import { IMCAsset } from "../../defines/IMCAsset";
import { IMCDataRequest } from "../../defines/IMCDataRequest";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCMedia } from "../../media/MCMedia";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import MCURL from "../../utils/MCURL";

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
    if ( !media ) {
      if ( !this.mInitPromises.has(mediaId) ) {
        this.mInitPromises.set(mediaId, this.initializeMedia(targetInfo));
      }
      media = await this.mInitPromises.get(mediaId)!;
    }
    return media.readwriteRetain();
  }

  protected getInstance(): HLSAsset {
    return this;
  }

  private async initializeMedia(targetInfo: MCURL.ProxyTargetInfo): Promise<IMCMedia> {
    const mediaId = targetInfo.mediaId;
    if ( !targetInfo.isRoot ) { // 请求的是 aes key, ts 等媒体;
      const media = new MCMedia(mediaId, this.mDir);
      await media.prepare();
      this.mMedias.set(mediaId, media);
      return media;
    }

    /**
     * 请求 playlist 时的处理:
     * 1. 获取代理媒体
     *    1.1 如果不存在, 则下载并生成代理内容保存在本地
     * */
    //
    // // 请求的是 playlist
    // if ( !this.mInitPlaylistPromise ) {
    //   this.mInitPlaylistPromise = this.initializePlaylist(targetInfo);
    // }
    // media = await this.mInitPlaylistPromise;
    // return media.readwriteRetain();
    throw new Error(``)
  }

  // private mInitPlaylistPromise: Promise<IMCMedia> | undefined = undefined;
  // private async initializePlaylist(requestTarget: string, targetInfo: MCURL.ProxyTargetInfo): Promise<IMCMedia> {
  //   const mediaId = targetInfo.mediaId;
  //   const media = new MCMedia(mediaId, this.mDir);
  //   await media.prepare();
  //   if ( !media.isAssembled ) {
  //     // 加载 playlist 的全部内容
  //     const request: IMCDataRequest = {
  //       requestTarget: requestTarget
  //     };
  //     media.fetch(request)
  //   }
  //   return media;
  // }
  //
  // /** 获取原始内容;
  //  *
  //  * 如果本地不存在, 则下载原始的 playlist;
  //  * */
  // private async fetchOriginalPlaylistMedia(targetInfo: MCURL.ProxyTargetInfo): Promise<MCMedia> {
  //   const mediaId = targetInfo.mediaId;
  //   if ( this.mInitPlaylistPromise === undefined ) {
  //     this.mInitPlaylistPromise = new Promise<IMCMedia>();
  //   }
  //   throw new Error(``)
  // }
  //
  // private async test(targetInfo: MCURL.ProxyTargetInfo): Promise<void> {
  //   const mediaId = targetInfo.mediaId;
  //   // wait media downloaded
  //
  //   const proxyId = `${mediaId}.proxy`;
  //   const proxyPrefix = `P${mediaId}}.proxy`;
  //   const proxyMedia = new MCMedia(proxyId, this.mDir, proxyPrefix);
  //   await proxyMedia.prepare();
  //   if ( !proxyMedia.isAssembled ) { // 数据不存在时, 开始下载;
  //
  //   }
  //   throw new Error(``)
  // }
}