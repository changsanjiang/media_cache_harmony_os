import { IMCReadwriteReference } from "./IMCReadwriteReference";
import { IMCDataRequest } from "./IMCDataRequest";
import { IMCDataResponse } from "./IMCDataResponse";
import { MCAbortSignal } from "../utils/MCAbortController";

/** 代表着一个媒体文件; 可以是一个 mp4 文件, 也可以是 hls 的 playlist 文件或 ts 等文件; */
export interface IMCMedia extends IMCReadwriteReference<IMCMedia> {
  readonly id: string;
  readonly metadataReady: boolean;
  readonly contentType: string | undefined; // mime type;
  readonly totalLength: number;

  readonly isAssembled: boolean;
  readonly completeness: Promise<number>; // 完成度; [0, 1];

  prepare(): Promise<void>;
  fetch(request: IMCDataRequest, signal?: MCAbortSignal): Promise<IMCDataResponse>; // 调用之前需要确保 media readwrite retained;
}