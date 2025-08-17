import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCDataResponse } from '../defines/IMCDataResponse';
import { IMCMedia, MCMediaCopyBehaviorOptions } from '../defines/IMCMedia';
import { IMCMediaContent } from '../defines/IMCMediaContent';
import { IMCMediaMetadata } from '../defines/IMCMediaMetadata';
import { MCMediaKind } from '../defines/MCMediaKind';
import { MCMediaContent } from '../media/MCMediaContent';
import { MCAbortSignal } from '../utils/MCAbortController';
import { MCReadwriteReference } from '../utils/MCReadwriteReference';

export class MCLocalMedia extends MCReadwriteReference<MCLocalMedia> implements IMCMedia {
  private mMetadata: IMCMediaMetadata;
  private mContent: IMCMediaContent;

  constructor(
    id: string,
    mediaKind: MCMediaKind,
    metadata: IMCMediaMetadata,
    filePath: string,
  ) {
    super();
    this.id = id;
    this.mediaKind = mediaKind;
    this.mMetadata = metadata;
    this.mContent = new MCMediaContent(id, 0, filePath, metadata.totalLength);
  }

  readonly id: string;
  readonly mediaKind: MCMediaKind;
  get metadataReady(): boolean { return true; }
  get contentType(): string { return this.mMetadata.contentType; }
  get totalLength(): number { return this.mMetadata.totalLength; }
  get isAssembled(): boolean { return true; }
  get completeness(): Promise<number> { return Promise.resolve(1.0); }
  get currentCachedSize(): number { return this.mMetadata.totalLength; }
  get abortSignal(): MCAbortSignal { throw new Error('Method not implemented.'); }
  protected getInstance(): MCLocalMedia { return this; }

  prepare(): Promise<void> { return Promise.resolve(); }
  probe(request: IMCDataRequest, signal?: MCAbortSignal | undefined): Promise<IMCMediaMetadata> { return Promise.resolve(this.mMetadata); }
  fetch(request: IMCDataRequest, clientId: number, signal?: MCAbortSignal | undefined): Promise<IMCDataResponse> {
    if ( this.mMetadata.totalLength > 0 ) {
      const requestRangeHeader = request.headers?.['range'];
      const contentRange = requestRangeHeader
    }
    throw new Error('Method not implemented.');
  }

  readAllData(): Promise<ArrayBuffer | undefined> { throw new Error('Method not implemented.'); }
  copyToDirectory(targetDir: string, options?: MCMediaCopyBehaviorOptions | undefined): Promise<void> { throw new Error('Method not implemented.'); }
}