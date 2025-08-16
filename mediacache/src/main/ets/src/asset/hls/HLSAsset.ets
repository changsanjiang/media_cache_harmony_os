import HLSDefines from "../../defines/HLSDefines";
import { IMCAsset } from "../../defines/IMCAsset";
import { IMCMedia } from "../../defines/IMCMedia";
import { MCAssetType } from "../../defines/MCAssetType";
import { MCMediaKind } from "../../defines/MCMediaKind";
import { MCMedia } from "../../media/MCMedia";
import { MCAbortController } from "../../utils/MCAbortController";
import MCConfigs from "../../utils/MCConfigs";
import { MCReadwriteReference } from "../../utils/MCReadwriteReference";
import { MCURL } from "../../utils/MCURL";
import MCUtils from "../../utils/MCUtils";
import MCAssetCacheManager from "../cachemgr/MCAssetCacheManager";
import HLSParser from "./HLSParser";
import { HLSPlaylist } from "./HLSPlaylist";

export class HLSAsset extends MCReadwriteReference<HLSAsset> implements IMCAsset {
  /** HLS 会有多个媒体文件; */
  private mMedias: Map<string, IMCMedia> = new Map();
  private mPlaylists: Map<string, HLSPlaylist> = new Map();
  private mDir: string;
  private mInitPromises: Map<string, Promise<IMCMedia>> = new Map();
  private mAbortController = new MCAbortController();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;

  get type(): MCAssetType {
    return MCAssetType.HLS;
  }

  get isCached(): boolean {
    return this.checkMediasCachedBy(this.mPlaylists.get(this.id));
  }

  get currentCachedSize(): number {
    return Array.from(this.mMedias.entries()).reduce((prev, media) => prev + media[1].currentCachedSize, 0);
  }

  async prepare(): Promise<void> {
    await this.loadPlaylists(this.id);
    await this.initializeMediasBy(this.mPlaylists.get(this.id));
  }

  async getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    if ( this.mAbortController.signal.isAborted ) {
      throw this.mAbortController.signal.reason!;
    }
    const targetInfo = MCURL.parseTarget(proxyPath);
    const mediaId = targetInfo.mediaId;
    const mediaKind = targetInfo.mediaKind;
    return this.getMedia(mediaId, mediaKind);
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

  /** Load playlist if content already assembled; */
  private async loadPlaylists(mediaId: string): Promise<void> {
    const playlistMedia = await this.getMedia(mediaId, MCMediaKind.PLAYLIST);
    if ( playlistMedia.isAssembled ) {
      const rawData = await playlistMedia.readAllData();
      if ( rawData ) {
        await this.initializePlaylist(mediaId, MCUtils.bufferToString(rawData));
      }
    }
  }

  private async initializePlaylist(mediaId: string, proxyContent: string): Promise<void> {
    if ( this.mPlaylists.get(mediaId) ) {
      return;
    }

    const playlist = new HLSPlaylist(proxyContent);
    this.mPlaylists.set(mediaId, playlist);

    if ( playlist.variantStream ) {
      const targetInfo = MCURL.parseTarget(playlist.variantStream.uri!);
      await this.loadPlaylists(targetInfo.mediaId); // 尝试加载 variant stream playlist
    }

    if ( playlist.audioRendition ) {
      const targetInfo = MCURL.parseTarget(playlist.audioRendition.uri!);
      await this.loadPlaylists(targetInfo.mediaId); // 尝试加载 audio rendition playlist
    }

    if ( playlist.videoRendition ) {
      const targetInfo = MCURL.parseTarget(playlist.videoRendition.uri!);
      await this.loadPlaylists(targetInfo.mediaId);  // 尝试加载 video rendition playlist
    }
  }

  private async initializeMedia(mediaId: string, mediaKind: MCMediaKind): Promise<IMCMedia> {
    let proxyHandler: ((requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer>) | undefined = undefined;
    // 代理 playlist 中的各个片段;
    if ( mediaKind === MCMediaKind.PLAYLIST ) {
      // MCMedia 的内容下载完成后回调;
      proxyHandler = async (requestUrl, currentUrl, data) => {
        const content = MCUtils.bufferToString(data);
        const proxyContent = await HLSParser.proxy(this.id, content, requestUrl, currentUrl, MCConfigs.variantStreamSelectionHandler, MCConfigs.renditionSelectionHandler);
        await this.initializePlaylist(mediaId, proxyContent);
        return MCUtils.stringToBuffer(proxyContent);
      }
    }

    const media = new MCMedia(mediaId, mediaKind, this.mDir, this.mAbortController.signal, proxyHandler);
    await media.prepare();
    this.mMedias.set(mediaId, media);
    return media;
  }

  private async initializeMediasBy(playlist: HLSPlaylist | undefined): Promise<void> {
    if ( playlist === undefined ) {
      return;
    }

    const allItems = playlist.allItems;
    if ( !allItems || allItems.length === 0 ) {
      return;
    }

    let itemIndex = 0;
    const concurrentLoadCount = 3;
    while (itemIndex < allItems.length ) {
      const promises: Promise<IMCMedia>[] = [];
      for (let p = 0; p < concurrentLoadCount; p++) {
        const item = allItems[itemIndex];
        const targetInfo = MCURL.parseTarget(item.uri!);
        promises.push(this.initializeMedia(targetInfo.mediaId, targetInfo.mediaKind));
        itemIndex += 1;
        if ( itemIndex >= allItems.length ) break;
      }
      await Promise.allSettled(promises);
    }

    const childPlaylistItems: HLSDefines.Item[] = [];
    const variantStream = playlist.variantStream;
    const audioRendition = playlist.audioRendition;
    const videoRendition = playlist.videoRendition;
    if ( variantStream ) {
      childPlaylistItems.push(variantStream);
    }
    if ( audioRendition ) {
      childPlaylistItems.push(audioRendition);
    }
    if ( videoRendition ) {
      childPlaylistItems.push(videoRendition);
    }

    for (let item of childPlaylistItems) {
      const targetInfo = MCURL.parseTarget(item.uri!);
      const childPlaylist = this.mPlaylists.get(targetInfo.mediaId);
      if ( childPlaylist ) await this.initializeMediasBy(childPlaylist);
    }
  }

  private checkMediasCachedBy(playlist: HLSPlaylist | undefined): boolean {
    if ( playlist === undefined ) {
      return false;
    }

    const allItems = playlist.allItems;
    if ( !allItems || allItems.length === 0 ) {
      return true;
    }

    for (let item of allItems) {
      const targetInfo = MCURL.parseTarget(item.uri!);
      const media = this.mMedias.get(targetInfo.mediaId);
      if ( !media || !media.isAssembled ) {
        return false;
      }
    }

    const childPlaylistItems: HLSDefines.Item[] = [];
    const variantStream = playlist.variantStream;
    const audioRendition = playlist.audioRendition;
    const videoRendition = playlist.videoRendition;
    if ( variantStream ) {
      childPlaylistItems.push(variantStream);
    }
    if ( audioRendition ) {
      childPlaylistItems.push(audioRendition);
    }
    if ( videoRendition ) {
      childPlaylistItems.push(videoRendition);
    }
    for (let item of childPlaylistItems) {
      const targetInfo = MCURL.parseTarget(item.uri!);
      const childPlaylist = this.mPlaylists.get(targetInfo.mediaId);
      const isCached = this.checkMediasCachedBy(childPlaylist);
      if ( !isCached ) {
        return false;
      }
    }
    return true;
  }

  protected getInstance(): HLSAsset {
    return this;
  }

  readwriteRetain(): HLSAsset {
    super.readwriteRetain();
    MCAssetCacheManager.onAssetReadwrite(this);
    return this;
  }

  async abort(error?: Error | undefined): Promise<void> {
    return this.mAbortController.abort(error);
  }
}


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