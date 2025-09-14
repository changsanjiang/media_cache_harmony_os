import { DashItem, DashTrack } from '../../defines/DashDefines';
import { IMCAsset } from '../../defines/IMCAsset';
import { IMCMedia } from '../../defines/IMCMedia';
import { MCAssetType } from '../../defines/MCAssetType';
import { MCMediaKind } from '../../defines/MCMediaKind';
import { MCMedia } from '../../media/MCMedia';
import { MCAbortController } from '../../utils/MCAbortController';
import MCConfigs from '../../utils/MCConfigs';
import { MCMediaIdGenerator } from '../../utils/MCMediaIdGenerator';
import { MCProxyURLUtils } from '../../utils/MCProxyURLUtils';
import { MCReadwriteReference } from '../../utils/MCReadwriteReference';
import MCUtils from '../../utils/MCUtils';
import MCAssetCacheManager from '../cachemgr/MCAssetCacheManager';
import { DashParser } from './DashParser';

export class DashAsset extends MCReadwriteReference<DashAsset> implements IMCAsset {
  private mDir: string;
  private mAbortController = new MCAbortController();
  // key: mediaId
  private mMedias: Map<string, IMCMedia> = new Map();
  private mSerialPromise: Promise<void> = Promise.resolve();
  private mTracks?: DashTrack[] = undefined;
  // key: media uri, value: media id;
  private mMediaIdMap: Map<string, string> = new Map(); // mTracks 有值后可用;

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;

  get type(): MCAssetType {
    return MCAssetType.DASH;
  }

  get isCached(): boolean {
    if ( this.mTracks == undefined ) {
      return false;
    }

    for ( const track of this.mTracks ) {
      const allItems = [...track.items];
      if ( track.initialization ) {
        allItems.push(track.initialization);
      }

      for ( let item of allItems ) {
        const mediaId = this.mMediaIdMap.get(item.uri);
        if ( mediaId == undefined ) {
          return false;
        }
        const media = this.mMedias.get(mediaId);
        if ( media == undefined ) {
          return false;
        }
      }
    }
    return true;
  }

  get currentCachedSize(): number {
    return Array.from(this.mMedias.entries()).reduce((prev, media) => prev + media[1].currentCachedSize, 0);
  }

  async prepare(): Promise<void> {
    const mpdMedia = await this.prepareMedia(this.id, MCMediaKind.PLAYLIST);
    if ( mpdMedia.isAssembled ) {
      const rawData = await mpdMedia.readAllData();
      if ( rawData ) {
        await this.extractTracks(MCUtils.bufferToString(rawData));
        if ( this.mTracks ) {
          for (let track of this.mTracks) {
            await this.loadMedias(track);
          }
        }
      }
    }
  }

  getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    if ( this.mAbortController.signal.isAborted ) {
      throw this.mAbortController.signal.reason!;
    }

    if ( this.mAbortController.signal.isAborted ) {
      throw this.mAbortController.signal.reason!;
    }
    const targetInfo = MCProxyURLUtils.parseTarget(proxyPath);
    const mediaId = targetInfo.mediaId;
    const mediaKind = targetInfo.mediaKind;
    return this.getMedia(mediaId, mediaKind);
  }

  protected getInstance(): DashAsset {
    return this;
  }

  readwriteRetain(): DashAsset {
    super.readwriteRetain();
    MCAssetCacheManager.onAssetReadwrite(this);
    return this;
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mAbortController.abort(error);
  }

  private async getMedia(mediaId: string, mediaKind: MCMediaKind): Promise<IMCMedia> {
    return this.enqueueTask(async () => this.mMedias.get(mediaId) ?? this.prepareMedia(mediaId, mediaKind));
  }

  private async prepareMedia(mediaId: string, mediaKind: MCMediaKind): Promise<IMCMedia> {
    let proxyHandler: ((requestUrl: string, currentUrl: string, data: ArrayBuffer) => Promise<ArrayBuffer>) | undefined = undefined;
    // 代理 playlist
    if ( mediaKind === MCMediaKind.PLAYLIST ) {
      // MCMedia 的内容下载完成后回调;
      proxyHandler = async (requestUrl, currentUrl, data) => {
        const content = MCUtils.bufferToString(data);
        const proxyContent = DashParser.proxy(
          content,
          this.id,
          requestUrl,
          currentUrl,
          MCConfigs.dashAdaptationSetSelectionHandler,
          MCConfigs.dashRepresentationSelectionHandler
        );
        await this.extractTracks(proxyContent);
        return MCUtils.stringToBuffer(proxyContent);
      }
    }

    const media = new MCMedia(mediaId, mediaKind, this.mDir, this.mAbortController.signal, proxyHandler);
    await media.prepare();
    this.mMedias.set(mediaId, media);
    return media;
  }

  private async prepareMediaBy(item: DashItem): Promise<IMCMedia> {
    const mediaId = await MCMediaIdGenerator.generate(item.uri);
    const mediaKind = MCMediaKind.FILE;
    return this.prepareMedia(mediaId, mediaKind);
  }

  private async extractTracks(mpdXml: string): Promise<void> {
    const mpd = DashParser.parse(mpdXml).mpd;
    this.mTracks = DashParser.extractTracks(mpd);

    for ( const track of this.mTracks ) {
      const allItems = [...track.items];
      if ( track.initialization ) {
        allItems.push(track.initialization);
      }
      const promises = allItems.map(it => MCMediaIdGenerator.generate(it.uri));
      const mediaIds = await Promise.all(promises);
      for ( let i = 0; i < mediaIds.length; ++i ) {
        this.mMediaIdMap.set(allItems[i].uri, mediaIds[i]);
      }
    }
  }

  private async loadMedias(track: DashTrack): Promise<void> {
    const allItems = [...track.items];
    if ( track.initialization ) {
      allItems.push(track.initialization);
    }

    let itemIndex = 0;
    const concurrent = 3;
    while ( itemIndex < allItems.length ) {
      const batch = allItems.slice(itemIndex, itemIndex + concurrent);
      const promises = batch.map(it => this.prepareMediaBy(it));
      await Promise.all(promises);
      itemIndex += concurrent;
    }
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