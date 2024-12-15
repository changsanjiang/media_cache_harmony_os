import { HLSPlaylist, MCUtils } from "../../../../../../Index";
import { IMCAsset } from "../../defines/IMCAsset";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCAssetType } from "../../defines/MCAssetType";
import { MCMedia } from "../../media/MCMedia";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import MCURL from "../../utils/MCURL";
import MCCacheManager from "../MCCacheManager";
import MCAssetManager from "../MCAssetManager";
import HLSParser from "./HLSParser";

export class HLSAsset extends MCReadwriteReference<HLSAsset> implements IMCAsset {
  /** HLS 会有多个媒体文件; */
  private mMedias: Map<string, IMCMedia> = new Map();
  private mDir: string;
  private mInitPromises: Map<string, Promise<IMCMedia>> = new Map();

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
  private mVariantStreamAsset?: HLSAsset = undefined;
  private mAudioRenditionAsset?: HLSAsset = undefined;
  private mVideoRenditionAsset?: HLSAsset = undefined;

  /// variantStreamAsset.masterAsset;
  /// audioRenditionAsset.masterAsset;
  /// videoRenditionAsset.masterAsset;
  // private mMasterAsset?: HLSAsset = undefined;
  //
  // private mVariantStreamItem?: HLSDefines.VariantStreamItem = undefined;
  // private mAudioRenditionItem?: HLSDefines.RenditionItem = undefined;
  // private mVideoRenditionItem?: HLSDefines.RenditionItem = undefined;

  private mPlaylist?: HLSPlaylist = undefined; // proxy playlist;

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

  async prepare(): Promise<void> {
    const playlistMedia = await this.initializeMedia(this.id, true);
    if ( playlistMedia.isAssembled ) {
      const rawData = await playlistMedia.readAllData();
      if ( rawData ) {
        await this.initializePlaylist(MCUtils.bufferToString(rawData));
      }
    }
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
        this.mInitPromises.set(mediaId, this.initializeMedia(mediaId, targetInfo.isRoot));
      }
      media = await this.mInitPromises.get(mediaId)!;
    }
    return media;
  }

  private async initializePlaylist(proxyContent: string): Promise<void> {
    if ( this.mPlaylist ) {
      return;
    }

    const playlist = new HLSPlaylist(proxyContent);
    if ( playlist.variantStream ) {
      this.mVariantStreamAsset = await MCAssetManager.getAssetBy(playlist.variantStream.uri!) as HLSAsset;
      // this.mVariantStreamAsset.mMasterAsset = this;
      // this.mVariantStreamItem = playlist.variantStream;
    }
    if ( playlist.audioRendition ) {
      this.mAudioRenditionAsset = await MCAssetManager.getAssetBy(playlist.audioRendition.uri!) as HLSAsset;
      // this.mAudioRenditionAsset.mMasterAsset = this;
      // this.mAudioRenditionItem = playlist.audioRendition;
    }
    if ( playlist.videoRendition ) {
      this.mVideoRenditionAsset = await MCAssetManager.getAssetBy(playlist.videoRendition.uri!) as HLSAsset;
      // this.mVideoRenditionAsset.mMasterAsset = this;
      // this.mVideoRenditionItem = playlist.videoRendition;
    }
    this.mPlaylist = playlist;
  }

  private async initializeMedia(mediaId: string, isRoot: boolean): Promise<IMCMedia> {
    try {
      let proxyHandler: ((requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer>) | undefined = undefined;
      if ( isRoot ) { // 代理所有的根文件(playlist);
        proxyHandler = async (requestUrl, currentUrl, data) => {
          const content = MCUtils.bufferToString(data);
          // variantStreamSelectionHandler?: HLSDefines.VariantStreamSelectionHandler, renditionSelectionHandler?: HLSDefines.RenditionSelectionHandler
          const proxyContent = await HLSParser.proxy(this.id, content, requestUrl, currentUrl);
          if ( mediaId === this.id ) await this.initializePlaylist(proxyContent);
          return MCUtils.stringToBuffer(proxyContent);
        }
      }

      const media = new MCMedia(mediaId, this.mDir, proxyHandler);
      await media.prepare();
      this.mMedias.set(mediaId, media);
      return media;
    }
    finally {
      this.mInitPromises.delete(mediaId);
    }
  }

  private async calculateCompleteness(): Promise<number> {
    if ( this.mPlaylist ) {
      if ( this.mPlaylist.allItems?.length === 0 ) {
        return 1;
      }

      if ( this.mPlaylist.segments ) {
        // calculate segments progress
        const promises = this.mPlaylist.segments.map((item) => this.getMediaBy(item.uri!).then((media) => media.completeness));
        return Promise.all(promises).then((progresses) => ((progresses.reduce((prev, cur) => prev + cur, 0)) / this.mPlaylist!.segments!.length));
      }
      else {
        return this.mVariantStreamAsset!.completeness;
      }
    }
    return 0;
  }

  protected getInstance(): HLSAsset {
    return this;
  }

  readwriteRetain(): HLSAsset {
    super.readwriteRetain();
    MCCacheManager.onAssetReadwrite(this);
    return this;
  }

  get cacheSize(): number {
    return Array.from(this.mMedias.entries()).reduce((prev, media) => prev + media[1].cacheSize, 0);
  }

  async removeAllCaches(): Promise<void> {
    for (let element of this.mMedias.entries()) {
      await element[1].removeAllCaches();
    }
  }
}