import { IMCDataRequest } from "./IMCDataRequest";
import { MCAbortSignal } from "../utils/MCAbortController";

/** 代表着一个媒体文件; 可以是一个 mp4 文件, 也可以是 hls 的 playlist 文件或 ts 等文件; */
export interface IMCMedia2 {
  readonly id: string;

  readonly isAssembled: boolean;
  readonly completeness: Promise<number>; // 完成度; [0, 1];

  prepare(): Promise<void>;
  fetch(request: IMCDataRequest, options: IMCDataFetchOptions): Promise<void>; // 请求数据;
}

export interface IMCDataFetchOptions {
  responseReceive: (responseHeaders: string) => void | Promise<void>;
  dataReceive: (data: ArrayBuffer) => void | Promise<void>;
  dataEnd?: () => void;
  signal?: MCAbortSignal;
}