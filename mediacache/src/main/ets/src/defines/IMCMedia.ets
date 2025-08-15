import { IMCReadwriteReference } from "./IMCReadwriteReference";
import { IMCDataRequest } from "./IMCDataRequest";
import { IMCDataResponse } from "./IMCDataResponse";
import { MCAbortSignal } from "../utils/MCAbortController";
import { IMCMediaMetadata } from "./IMCMediaMetadata";
import { MCMediaKind } from "./MCMediaKind";
import { MCCopyFileConflictStrategy } from "./MCCopyFileConflictStrategy";

/** 代表着一个媒体文件; 可以是一个 mp4 文件, 也可以是 hls 的 playlist 文件或 ts 等文件; */
export interface IMCMedia extends IMCReadwriteReference<IMCMedia> {
  readonly id: string;
  readonly mediaKind: MCMediaKind;
  readonly metadataReady: boolean;
  readonly contentType: string | undefined; // mime type;
  readonly totalLength: number;

  readonly isAssembled: boolean;
  readonly completeness: Promise<number>; // 完成度; [0, 1];
  readonly currentCachedSize: number; // 当前已缓存的数据大小(单位: 字节);

  prepare(): Promise<void>;
  probe(request: IMCDataRequest, signal?: MCAbortSignal): Promise<IMCMediaMetadata>;
  fetch(request: IMCDataRequest, clientId: number, signal?: MCAbortSignal): Promise<IMCDataResponse>;

  // 如果数据组合完成, 通过该方法可以获取媒体所有数据;
  // 请谨慎使用, 该方法仅适合获取小文件的所有数据;
  readAllData(): Promise<ArrayBuffer | undefined>;

  readonly abortSignal: MCAbortSignal; // 任务中止信号;

  // 将元数据和媒体文件复制到目标目录;
  // 注意: 只有在所有数据下载完毕后(completeness === 1.0), 才能调用该方法;
  copyToDirectory(targetDir: string, options?: MCMediaCopyBehaviorOptions): Promise<void>;
}

export interface MCMediaCopyBehaviorOptions {
  /**
   * 冲突处理策略：
   * - Skip      => 直接跳过
   * - Overwrite => 覆盖目标文件
   * - Throw     => 抛出错误
   *
   * 默认为 Throw。
   */
  conflictStrategy?: MCCopyFileConflictStrategy;
}