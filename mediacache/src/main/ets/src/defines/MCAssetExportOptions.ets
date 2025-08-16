import { MCAbortSignal } from "../utils/MCAbortController";
import { MCCopyFileConflictStrategy } from "./MCCopyFileConflictStrategy";

export interface MCAssetExportOptions {
  additionalHeaders?: Record<string, string>;
  conflictStrategy?: MCCopyFileConflictStrategy; // default MCCopyFileConflictStrategy.Throw
  onProgress?: (progress: number) => void;
  signal?: MCAbortSignal; // 中止信号
}