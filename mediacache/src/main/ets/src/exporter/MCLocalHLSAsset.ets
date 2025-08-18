import { IMCAsset } from '../defines/IMCAsset';
import { IMCMedia } from '../defines/IMCMedia';
import { MCAssetType } from '../defines/MCAssetType';
import { MCMediaKind } from '../defines/MCMediaKind';
import { MCMediaContent } from '../media/MCMediaContent';
import { MCMediaMetadataStore } from '../media/MCMediaContentProvider';
import { MCProxyDirUtils } from '../utils/MCProxyDirUtils';
import { MCReadwriteReference } from '../utils/MCReadwriteReference';
import { MCLocalMedia } from './MCLocalMedia';
import { MCMediaExportPath } from './MCMediaExportPath';
import { fileIo } from '@kit.CoreFileKit';
import HLSParser from '../asset/hls/HLSParser';
import MCUtils from '../utils/MCUtils';
import { MCMediaBufferContent } from '../media/MCMediaBufferContent';
import { MCAbortController } from '../utils/MCAbortController';
import { IMCMediaMetadata } from '../defines/IMCMediaMetadata';

export class MCLocalHLSAsset extends MCReadwriteReference<MCLocalHLSAsset> implements IMCAsset {
  private mDir: string;
  private mMedias: Map<string, IMCMedia> = new Map();
  private mAbortController = new MCAbortController();
  private mSerialPromise = Promise.resolve();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;
  get type(): MCAssetType { return MCAssetType.HLS; }
  get isCached(): boolean { throw new Error("Method not implemented.") }
  get currentCachedSize(): number { throw new Error("Method not implemented.") };

  prepare(): Promise<void> {
    return Promise.resolve();
  }

  getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    return this.enqueueTask(async () => {
      const targetInfo = MCProxyDirUtils.parseTarget(proxyPath);
      const mediaId = targetInfo.mediaId;
      const mediaKind = targetInfo.mediaKind;
      return this.mMedias.get(mediaId) ?? await this.initMedia(mediaId, mediaKind);
    });
  }

  protected getInstance(): MCLocalHLSAsset { return this; }
  abort(error?: Error | undefined): Promise<void> { return this.mAbortController.abort(error); }

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

  private async initMedia(mediaId: string, mediaKind: MCMediaKind): Promise<IMCMedia> {
    const metadataPath = MCMediaExportPath.resolveMetadataDestPath(mediaId, mediaKind, this.mDir);
    const entries = await MCMediaMetadataStore.loadMetadata(metadataPath);
    if ( !entries ) {
      throw new Error(`Preparation failed: unable to load metadata at ${metadataPath}`);
    }
    const metadata = entries[0];
    const contentPath = MCMediaExportPath.resolveContentDestPath(mediaId, mediaKind, this.mDir);

    switch (mediaKind) {
      case MCMediaKind.FILE: {
        const content = new MCMediaContent(mediaId, 0, contentPath, metadata.totalLength);
        const media = new MCLocalMedia(mediaId, mediaKind, metadata, content, this.mAbortController.signal);
        await media.prepare();
        this.mMedias.set(mediaId, media);
        return media;
      }
      case MCMediaKind.PLAYLIST: {
        const playlist = await fileIo.readText(contentPath, { encoding: 'utf-8' });
        const transferred = await HLSParser.transferProxy(playlist, this.mDir);
        const buffer = MCUtils.stringToBuffer(transferred);
        const content = new MCMediaBufferContent(mediaId, 0, buffer);
        const newMetadata: IMCMediaMetadata = {
          contentType: metadata.contentType,
          totalLength: buffer.byteLength,
          byteRangeAccessSupported: true,
        };
        const media = new MCLocalMedia(mediaId, mediaKind, newMetadata, content, this.mAbortController.signal);
        await media.prepare();
        this.mMedias.set(mediaId, media);
        return media;
      }
    }
  }
}