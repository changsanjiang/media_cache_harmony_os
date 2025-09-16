import { IMCAsset } from '../../defines/IMCAsset';
import { IMCMedia } from '../../defines/IMCMedia';
import { MCAssetType } from '../../defines/MCAssetType';
import { MCMediaKind } from '../../defines/MCMediaKind';
import { MCMedia } from '../../media/MCMedia';
import { MCAbortController } from '../../utils/MCAbortController';
import MCConfigs from '../../utils/MCConfigs';
import MCFileIOUtils from '../../utils/MCFileIOUtils';
import { MCProxyURLUtils } from '../../utils/MCProxyURLUtils';
import { MCReadwriteReference } from '../../utils/MCReadwriteReference';
import MCUtils from '../../utils/MCUtils';
import MCAssetCacheManager from '../cachemgr/MCAssetCacheManager';
import { DashParser } from './DashParser';

export class DashAsset extends MCReadwriteReference<DashAsset> implements IMCAsset {
  private mDir: string;
  private mAbortController = new MCAbortController();
  // key: mediaId, value: media
  private mPreparedMedias: Map<string, IMCMedia> = new Map();
  private mColdCacheSize = 0;
  private mSerialPromise: Promise<void> = Promise.resolve();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;

  get type(): MCAssetType {
    return MCAssetType.DASH;
  }

  get currentCachedSize(): number {
    return this.mColdCacheSize + Array.from(this.mPreparedMedias.entries()).reduce((prev, media) => prev + media[1].currentCachedSize, 0);
  }

  async prepare(): Promise<void> {
    // 计算本地缓存文件的大小
    this.mColdCacheSize = await MCFileIOUtils.calculateTotalBytes(this.mDir);
  }

  getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
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
    return this.enqueueTask(async () => this.mPreparedMedias.get(mediaId) ?? this.prepareMedia(mediaId, mediaKind));
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
        return MCUtils.stringToBuffer(proxyContent);
      }
    }

    const media = new MCMedia(mediaId, mediaKind, this.mDir, this.mAbortController.signal, proxyHandler);
    await media.prepare();
    this.mPreparedMedias.set(mediaId, media);
    this.mColdCacheSize -= media.currentCachedSize;
    return media;
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