import { HLSPlaylist, MCUtils } from "../../../../../../Index";
import { IMCAsset } from "../../defines/IMCAsset";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCAssetType } from "../../defines/MCAssetType";
import { MCMediaKind } from "../../defines/MCMediaKind";
import { MCMedia } from "../../media/MCMedia";
import { MCAbortController } from "../../utils/MCAbortController";
import MCArrayUtils from "../../utils/MCArrayUtils";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import { MCRetryPromise } from "../../utils/MCRetryPromise";
import MCURL from "../../utils/MCURL";
import MCAssetCacheManager from "../cachemgr/MCAssetCacheManager";
import MCAssetManager from "../MCAssetManager";
import HLSParser from "./HLSParser";
import List from "@ohos.util.List";
import HLSDefines from "../../defines/HLSDefines";

export class HLSAsset extends MCReadwriteReference<HLSAsset> implements IMCAsset {
  /** HLS 会有多个媒体文件; */
  private mMedias: Map<string, IMCMedia> = new Map();
  private mDir: string;
  private mInitPromises: Map<string, Promise<IMCMedia>> = new Map();
  private mAbortController = new MCAbortController();

  /// ----- master.m3u8
  /// #EXTM3U
  /// #EXT-X-VERSION:6
  /// #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_group",NAME="English",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="en",URI="https://example.com/audio/english.m3u8"
  /// #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_group",NAME="Spanish",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE="es",URI="https://example.com/audio/spanish.m3u8"
  /// #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subtitles_group",NAME="English",DEFAULT=NO,AUTOSELECT=YES,URI="https://example.com/subtitles/english.vtt"
  /// #EXT-X-STREAM-INF:BANDWIDTH=1280000,RESOLUTION=1280x720,AUDIO="audio_group"
  /// 720p_output.m3u8
  /// #EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=854x480,AUDIO="audio_group"
  /// 480p_output.m3u8
  ///
  /// ----- variant_stream: 720p_output.m3u8
  /// 720p_output.m3u8
  /// #EXTM3U
  /// #EXT-X-VERSION:6
  /// #EXT-X-TARGETDURATION:10
  /// #EXT-X-MEDIA-SEQUENCE:0
  /// #EXT-X-INDEPENDENT-SEGMENTS
  /// #EXTINF:10.0,
  /// 720p_segment_000.ts
  /// #EXT-X-ENDLIST
  ///
  /// ----- audio_rendition: english.m3u8
  /// #EXTM3U
  /// #EXT-X-VERSION:6
  /// #EXT-X-TARGETDURATION:10
  /// #EXT-X-MEDIA-SEQUENCE:0
  /// #EXTINF:10.0,
  /// english_segment_000.ts
  /// #EXT-X-ENDLIST

  private mMasterPlaylist?: HLSPlaylist = undefined;

  private mVariantStreamMediaId?: string = undefined;
  private mVariantStreamPlaylist?: HLSPlaylist = undefined;

  private mAudioRenditionMediaId?: string = undefined;
  private mAudioRenditionPlaylist?: HLSPlaylist = undefined;

  private mVideoRenditionMediaId?: string = undefined;
  private mVideoRenditionPlaylist?: HLSPlaylist = undefined;

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;

  get type(): MCAssetType {
    return MCAssetType.HLS;
  }

  get completeness(): Promise<number> {
    return this.calculateCompleteness();
  }

  prepare(): Promise<void> {
    return this.loadPlaylist(this.id);
  }

  async getMediaBy(requestTarget: string): Promise<IMCMedia> {
    const targetInfo = MCURL.parse(requestTarget);
    if ( targetInfo.assetId !== this.id ) {
      throw new Error(`xxx`);
    }
    const mediaId = targetInfo.mediaId;
    const mediaKind = targetInfo.mediaKind;
    return this.getMedia(mediaId, mediaKind);
  }

  /** Load playlist if content already assembled; */
  private async loadPlaylist(mediaId: string): Promise<void> {
    const playlistMedia = await this.getMedia(mediaId, MCMediaKind.PLAYLIST);
    if ( playlistMedia.isAssembled ) {
      const rawData = await playlistMedia.readAllData();
      if ( rawData ) {
        await this.initializePlaylist(mediaId, MCUtils.bufferToString(rawData));
      }
    }
  }

  private async initializePlaylist(mediaId: string, proxyContent: string): Promise<void> {
    if ( mediaId === this.id ) {
      if ( !this.mMasterPlaylist ) {
        this.mMasterPlaylist = new HLSPlaylist(proxyContent);

        if ( this.mMasterPlaylist.variantStream ) {
          const targetInfo = MCURL.parse(this.mMasterPlaylist.variantStream.uri!);
          this.mVariantStreamMediaId = targetInfo.mediaId;
          await this.loadPlaylist(targetInfo.mediaId);
        }

        if ( this.mMasterPlaylist.audioRendition ) {
          const targetInfo = MCURL.parse(this.mMasterPlaylist.audioRendition.uri!);
          this.mVariantStreamMediaId = targetInfo.mediaId;
          await this.loadPlaylist(targetInfo.mediaId);
        }

        if ( this.mMasterPlaylist.videoRendition ) {
          const targetInfo = MCURL.parse(this.mMasterPlaylist.videoRendition.uri!);
          this.mVariantStreamMediaId = targetInfo.mediaId;
          await this.loadPlaylist(targetInfo.mediaId);
        }
      }
    }
    else if ( mediaId === this.mVariantStreamMediaId ) {
      if ( !this.mVariantStreamPlaylist ) this.mVariantStreamPlaylist = new HLSPlaylist(proxyContent);
    }
    else if ( mediaId === this.mAudioRenditionMediaId ) {
      if ( !this.mAudioRenditionPlaylist ) this.mAudioRenditionPlaylist = new HLSPlaylist(proxyContent);
    }
    else if ( mediaId === this.mVideoRenditionMediaId ) {
      if ( !this.mVideoRenditionPlaylist ) this.mVideoRenditionPlaylist = new HLSPlaylist(proxyContent);
    }
  }

  private async getMedia(mediaId: string, mediaKind: MCMediaKind): Promise<IMCMedia> {
    let media: IMCMedia | undefined = this.mMedias.get(mediaId);
    if ( media === undefined ) {
      let promise = this.mInitPromises.get(mediaId);
      if ( promise === undefined ) {
        promise = this.initializeMedia(mediaId, mediaKind);
        this.mInitPromises.set(mediaId, promise);
        try {
          media = await promise;
        }
        finally {
          this.mInitPromises.delete(mediaId);
        }
      }
      else {
        media = await promise;
      }
    }
    return media;
  }

  private async initializeMedia(mediaId: string, mediaKind: MCMediaKind): Promise<IMCMedia> {
    let proxyHandler: ((requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer>) | undefined = undefined;
    // 代理 playlist 中的各个片段;
    if ( mediaKind === MCMediaKind.PLAYLIST ) {
      // MCMedia 的内容下载完成后回调;
      proxyHandler = async (requestUrl, currentUrl, data) => {
        const content = MCUtils.bufferToString(data);
        // variantStreamSelectionHandler?: HLSDefines.VariantStreamSelectionHandler, renditionSelectionHandler?: HLSDefines.RenditionSelectionHandler
        const proxyContent = await HLSParser.proxy(this.id, content, requestUrl, currentUrl);
        await this.initializePlaylist(mediaId, proxyContent);
        return MCUtils.stringToBuffer(proxyContent);
      }
    }

    const media = new MCMedia(mediaId, this.mDir, this.mAbortController.signal, proxyHandler);
    await media.prepare();
    this.mMedias.set(mediaId, media);
    return media;
  }

  private async findMedia(mediaId: string): Promise<IMCMedia | undefined> {
    return undefined;
  }

  private async calculateCompleteness(): Promise<number> {
    if ( this.mMasterPlaylist ) {
      if ( this.mMasterPlaylist.allItems?.length === 0 ) {
        return 1;
      }

      // if ( this.mMasterPlaylist.segments ) {
      //   // calculate segments progress
      //   const promises = this.mMasterPlaylist.segments.map((item) => this.getMediaBy(item.uri!).then((media) => media.completeness));
      //   return Promise.all(promises).then((progresses) => ((progresses.reduce((prev, cur) => prev + cur, 0)) / this.mMasterPlaylist!.segments!.length));
      // }
      // else {
      //   return this.mVariantStreamAsset!.completeness;
      // }
    }
    return 0;
  }

  private async calculateCompleteness2(): Promise<number> {
    if ( !this.mMasterPlaylist ) {
      return 0;
    }

    if ( this.mMasterPlaylist.variantStream === undefined ) {
      return this.calculateCompletenessByPlaylist(this.mMasterPlaylist);
    }

    let denominator = 1;
    if ( this.mMasterPlaylist.audioRendition ) denominator += 1;
    if ( this.mMasterPlaylist.videoRendition ) denominator += 1;
    if ( this.mMasterPlaylist.subtitlesRendition ) denominator += 1;

    let numerator = 0;
    if ( this.mVariantStreamPlaylist ) {
      const playlists: [HLSPlaylist] = [this.mVariantStreamPlaylist];
      if ( this.mAudioRenditionPlaylist ) playlists.push(this.mAudioRenditionPlaylist);
      if ( this.mVideoRenditionPlaylist ) playlists.push(this.mVideoRenditionPlaylist);
      playlists.map(playlist => this.calculateCompletenessByPlaylist(playlist));
    }

    //  TODO next 比例问题

    return 0;
  }

  private async calculateCompletenessByPlaylist(playlist: HLSPlaylist): Promise<number> {
    if (!playlist.allItems || playlist.allItems.length === 0) {
      return 1;
    }

    if (playlist.segments) {
      return this.calculateCompletenessBySegments(playlist.segments);
    }
    return 0;
  }

  private async calculateCompletenessBySegments(segments: HLSDefines.SegmentItem[]): Promise<number> {
    const promises = segments.map((item) => this.findMedia(MCURL.parse(item.uri!).mediaId).then((media) => media?.completeness ?? 0, () => 0));
    return Promise.all(promises).then((progresses) => ((progresses.reduce((prev, cur) => prev + cur, 0)) / segments.length));
  }

  protected getInstance(): HLSAsset {
    return this;
  }

  readwriteRetain(): HLSAsset {
    super.readwriteRetain();
    MCAssetCacheManager.onAssetReadwrite(this);
    return this;
  }

  get cacheSize(): number {
    return Array.from(this.mMedias.entries()).reduce((prev, media) => prev + media[1].cacheSize, 0);
  }

  async abort(error?: Error | undefined): Promise<void> {
    return this.mAbortController.abort(error);
  }
}