import { IMCReadwriteReference } from "./IMCReadwriteReference";
import { IMCDataRequest } from "./IMCDataRequest";
import { IMCDataResponse } from "./IMCDataResponse";
import { MCAbortSignal } from "../utils/MCAbortController";
import { IMCMediaMetadata } from "./IMCMediaMetadata";

/** 代表着一个媒体文件; 可以是一个 mp4 文件, 也可以是 hls 的 playlist 文件或 ts 等文件; */
export interface IMCMedia extends IMCReadwriteReference<IMCMedia> {
  readonly id: string;
  readonly metadataReady: boolean;
  readonly contentType: string | undefined; // mime type;
  readonly totalLength: number;

  readonly isAssembled: boolean;
  readonly completeness: Promise<number>; // 完成度; [0, 1];

  prepare(): Promise<void>;
  probe(request: IMCDataRequest, signal?: MCAbortSignal): Promise<IMCMediaMetadata>;
  fetch(request: IMCDataRequest, signal?: MCAbortSignal): Promise<IMCDataResponse>;

  // 如果数据组合完成, 通过该方法可以获取媒体所有数据;
  // 请谨慎使用, 该方法仅适合获取小文件的所有数据;
  readAllData(): Promise<ArrayBuffer | undefined>;
}