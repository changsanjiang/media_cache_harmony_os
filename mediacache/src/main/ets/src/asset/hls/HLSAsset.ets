import { IMCAsset } from '../../defines/IMCAsset';
import { IMCMedia } from '../../defines/IMCMedia';
import { MCAssetType } from '../../defines/MCAssetType';
import { MCMediaKind } from '../../defines/MCMediaKind';
import { MCMedia } from '../../media/MCMedia';
import { MCAbortController } from '../../utils/MCAbortController';
import MCConfigs from '../../utils/MCConfigs';
import { MCReadwriteReference } from '../../utils/MCReadwriteReference';
import { MCProxyURLUtils } from '../../utils/MCProxyURLUtils';
import MCUtils from '../../utils/MCUtils';
import MCAssetCacheManager from '../cachemgr/MCAssetCacheManager';
import HLSParser from './HLSParser';
import MCFileIOUtils from '../../utils/MCFileIOUtils';

export class HLSAsset extends MCReadwriteReference<HLSAsset> implements IMCAsset {
  /** HLS 会有多个媒体文件; */
  private mPreparedMedias: Map<string, IMCMedia> = new Map();
  private mColdCacheSize = 0;
  private mDir: string;
  private mAbortController = new MCAbortController();
  private mSerialPromise: Promise<void> = Promise.resolve();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;

  get type(): MCAssetType {
    return MCAssetType.HLS;
  }

  get currentCachedSize(): number {
    return this.mColdCacheSize + Array.from(this.mPreparedMedias.entries()).reduce((prev, media) => prev + media[1].currentCachedSize, 0);
  }

  async prepare(): Promise<void> {
    this.mColdCacheSize = await MCFileIOUtils.calculateTotalBytes(this.mDir);
  }

  async getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    if ( this.mAbortController.signal.isAborted ) {
      throw this.mAbortController.signal.reason!;
    }
    const targetInfo = MCProxyURLUtils.parseTarget(proxyPath);
    const mediaId = targetInfo.mediaId;
    const mediaKind = targetInfo.mediaKind;
    return this.getMedia(mediaId, mediaKind);
  }

  private async getMedia(mediaId: string, mediaKind: MCMediaKind): Promise<IMCMedia> {
    return this.enqueueTask(async () => this.mPreparedMedias.get(mediaId) ?? this.prepareMedia(mediaId, mediaKind));
  }

  private async prepareMedia(mediaId: string, mediaKind: MCMediaKind): Promise<IMCMedia> {
    let proxyHandler: ((requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer>) | undefined = undefined;
    // 代理 playlist 中的各个片段;
    if ( mediaKind === MCMediaKind.PLAYLIST ) {
      // MCMedia 的内容下载完成后回调;
      proxyHandler = async (requestUrl, currentUrl, data) => {
        const content = MCUtils.bufferToString(data);
        const proxyContent = await HLSParser.proxy(content, this.id, requestUrl, currentUrl, MCConfigs.variantStreamSelectionHandler, MCConfigs.renditionSelectionHandler);
        return MCUtils.stringToBuffer(proxyContent);
      }
    }

    const media = new MCMedia(mediaId, mediaKind, this.mDir, this.mAbortController.signal, proxyHandler);
    await media.prepare();
    this.mPreparedMedias.set(mediaId, media);
    this.mColdCacheSize -= media.currentCachedSize;
    return media;
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

  private enqueueTask<T>(task: () => Promise<T>): Promise<T> {
    const run = this.mSerialPromise
      .catch((err: Error) => {  // swallow previous errors
        console.error('Previous task failed:', err);
      })
      .then(() => task());

    // Maintain the chain
    this.mSerialPromise = run.then(() => {}, (err: Error) => {
      console.error('Previous task failed:', err);
    });
    return run;
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