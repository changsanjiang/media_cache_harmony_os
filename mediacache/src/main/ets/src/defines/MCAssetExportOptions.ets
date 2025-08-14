import { MCAbortSignal } from "../utils/MCAbortController";

export interface MCAssetExportOptions {
  overwrite?: boolean;    // 是否覆盖目录文件
  signal?: MCAbortSignal; // 中止信号
  onProgress?: (progress: number) => void;
}