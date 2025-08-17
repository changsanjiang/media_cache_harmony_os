import { IMCAsset } from '../defines/IMCAsset';
import { IMCMedia } from '../defines/IMCMedia';
import { MCAssetType } from '../defines/MCAssetType';
import { MCMediaKind } from '../defines/MCMediaKind';
import { MCMediaMetadataStore } from '../media/MCMediaContentProvider';
import { MCAbortController } from '../utils/MCAbortController';
import { MCReadwriteReference } from '../utils/MCReadwriteReference';
import { MCLocalMedia } from './MCLocalMedia';
import { MCMediaExportPath } from './MCMediaExportPath';

export class MCLocalFILEAsset extends MCReadwriteReference<MCLocalFILEAsset> implements IMCAsset {
  private mDir: string;
  private mMedia: IMCMedia | undefined = undefined;
  private mAbortController = new MCAbortController();

  constructor(id: string, dir: string) {
    super();
    this.id = id;
    this.mDir = dir;
  }

  readonly id: string;
  get type(): MCAssetType {
    return MCAssetType.FILE_BASED;
  }
  get isCached(): boolean {
    return true;
  }
  get currentCachedSize(): number {
    return 0;
  }

  async prepare(): Promise<void> {
    const metadataPath = MCMediaExportPath.resolveMetadataDestPath(this.id, MCMediaKind.FILE, this.mDir);
    const entries = await MCMediaMetadataStore.loadMetadata(metadataPath);
    if ( !entries ) {
      throw new Error(`Preparation failed: unable to load metadata at ${metadataPath}`);
    }
    const metadata = entries[0];
    const contentPath = MCMediaExportPath.resolveContentDestPath(this.id, MCMediaKind.FILE, this.mDir);
    this.mMedia = new MCLocalMedia(this.id, MCMediaKind.FILE, metadata, contentPath);
  }

  async getMediaByProxyPath(proxyPath: string): Promise<IMCMedia> {
    return this.mMedia!;
  }

  protected getInstance(): MCLocalFILEAsset {
    return this;
  }

  abort(error?: Error | undefined): Promise<void> {
    return this.mAbortController.abort(error);
  }
}