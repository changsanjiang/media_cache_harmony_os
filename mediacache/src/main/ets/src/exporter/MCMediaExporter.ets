import { IMCDataRequest } from '../defines/IMCDataRequest';
import { IMCMedia } from '../defines/IMCMedia';
import { MCCopyFileConflictStrategy } from '../defines/MCCopyFileConflictStrategy';
import { MCAssetPrefetchUtils } from '../prefetcher/MCAssetPrefetchUtils';
import { MCMediaDataPrefetcher } from '../prefetcher/MCMediaDataPrefetcher';
import { MCAbortSignal } from '../utils/MCAbortController';

export interface IMCMediaExporter {
  export(): Promise<void>;
}

export interface MCMediaExportOptions {
  conflictStrategy?: MCCopyFileConflictStrategy;
  onProgress?: (progress: number) => void;
  signal?: MCAbortSignal;
}

export class MCMediaExporter implements IMCMediaExporter {
  private mMedia: IMCMedia;
  private mRequest: IMCDataRequest;
  private mTargetDir: string;
  private mOptions?: MCMediaExportOptions;

  constructor(
    media: IMCMedia,
    request: IMCDataRequest,
    targetDir: string,
    options?: MCMediaExportOptions,
  ) {
    this.mMedia = media;
    this.mRequest = request;
    this.mTargetDir = targetDir;
    this.mOptions = options;
  }

  async export(): Promise<void> {
    const signal = this.mOptions?.signal;
    MCAssetPrefetchUtils.checkAbortSignal(signal);

    // 为了确保数据完整性
    // 1. 先通过预加载将所有数据缓存在本地
    // 2. 再将媒体数据复制到指定目录

    // 预加载数据
    const completeness = await this.mMedia.completeness;
    if ( completeness < 1.0 ) {
      const prefecher = new MCMediaDataPrefetcher(
        this.mMedia,
        this.mRequest,
        (receivedLength, expectedLength) => this.mOptions?.onProgress?.(receivedLength / expectedLength),
        this.mOptions?.signal
      );
      await prefecher.prefetch();
    }

    // copy到指定目录
    await this.mMedia.copyToDirectory(this.mTargetDir, {
      conflictStrategy: this.mOptions?.conflictStrategy,
    });
  }
}