import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCDataOkResponse, IMCDataPartialContentResponse, IMCDataResponse } from '../defines/IMCDataResponse';
import { parseRequestRange } from '../defines/IMCHttpRequestRange';
import { IMCMedia, MCMediaCopyBehaviorOptions } from '../defines/IMCMedia';
import { IMCMediaContent } from '../defines/IMCMediaContent';
import { IMCMediaMetadata } from '../defines/IMCMediaMetadata';
import { MCLogModule } from '../defines/MCLogModule';
import { MCMediaKind } from '../defines/MCMediaKind';
import { MCMediaFileContentLoader } from '../media/MCMediaFileContentLoader';
import { MCAbortSignal } from '../utils/MCAbortController';
import MCLogger from '../utils/MCLogger';
import { MCRange } from '../utils/MCRange';
import { MCReadwriteReference } from '../utils/MCReadwriteReference';

export class MCLocalMedia extends MCReadwriteReference<MCLocalMedia> implements IMCMedia {
  private mMetadata: IMCMediaMetadata;
  private mContent: IMCMediaContent;

  constructor(
    id: string,
    mediaKind: MCMediaKind,
    metadata: IMCMediaMetadata,
    content: IMCMediaContent,
    signal: MCAbortSignal,
  ) {
    super();
    this.id = id;
    this.mediaKind = mediaKind;
    this.mMetadata = metadata;
    this.mContent = content;
    this.abortSignal = signal;
  }

  readonly id: string;
  readonly mediaKind: MCMediaKind;
  get metadataReady(): boolean { return true; }
  get contentType(): string { return this.mMetadata.contentType; }
  get totalLength(): number { return this.mMetadata.totalLength; }
  get isAssembled(): boolean { return true; }
  get completeness(): Promise<number> { return Promise.resolve(1.0); }
  get currentCachedSize(): number { return this.mMetadata.totalLength; }
  readonly abortSignal: MCAbortSignal;
  protected getInstance(): MCLocalMedia { return this; }

  prepare(): Promise<void> { return Promise.resolve(); }
  probe(request: IMCDataRequest, signal?: MCAbortSignal | undefined): Promise<IMCMediaMetadata> { return Promise.resolve(this.mMetadata); }
  async fetch(request: IMCDataRequest, clientId: number, signal?: MCAbortSignal | undefined): Promise<IMCDataResponse> {
    MCLogger.debug(MCLogModule.MCLocalMedia, () => `[mediaId: ${this.id}][clientId: ${clientId}] Fetching with request: ${JSON.stringify(request)}`);

    // empty content;
    if ( this.mMetadata.totalLength <= 0 ) {
      MCLogger.info(MCLogModule.MCLocalMedia, () => `[mediaId: ${this.id}][clientId: ${clientId}] TotalLength=0, returning empty 200 response`);

      const response: IMCDataOkResponse = {
        statusCode: 200,
        contentType: this.mMetadata.contentType,
        contentLength: 0,
        contentLoaders: []
      };
      return response;
    }

    const requestRangeHeader = request.headers?.['range'];
    const readRange = requestRangeHeader ? parseRequestRange(requestRangeHeader).toRange(this.mMetadata.totalLength) : new MCRange(0, this.mMetadata.totalLength);
    MCLogger.debug(MCLogModule.MCLocalMedia, () => `[mediaId: ${this.id}]: Read range parsed as: ${JSON.stringify(readRange)}`);
    const loader = new MCMediaFileContentLoader(clientId, 0, this.mContent, readRange);

    // 206
    if ( requestRangeHeader ) {
      MCLogger.info(MCLogModule.MCLocalMedia, () => `[mediaId: ${this.id}][clientId: ${clientId}] Returning 206 Partial Content, range=${JSON.stringify(readRange)}, totalLength=${this.mMetadata.totalLength}`);

      const response: IMCDataPartialContentResponse = {
        statusCode: 206,
        contentType: this.mMetadata.contentType,
        contentRange: readRange,
        totalLength: this.mMetadata.totalLength,
        contentLoaders: [loader]
      };
      return response;
    }

    // 200
    MCLogger.info(MCLogModule.MCLocalMedia, () => `[mediaId: ${this.id}][clientId: ${clientId}] Returning 200 OK, totalLength=${this.mMetadata.totalLength}`);

    const response: IMCDataOkResponse = {
      statusCode: 200,
      contentType: this.mMetadata.contentType,
      contentLength: this.mMetadata.totalLength,
      byteRangeAccessSupported: true,
      contentLoaders: [loader]
    };
    return response;
  }

  readAllData(): Promise<ArrayBuffer | undefined> { throw new Error('Method not implemented.'); }
  copyFiles(metadataDestPath: string, contentDestPath: string, options?: MCMediaCopyBehaviorOptions | undefined): Promise<void> { throw new Error('Method not implemented.')}
}