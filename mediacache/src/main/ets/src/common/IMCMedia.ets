import { IMCMediaContentLoader } from "./IMCMediaContentLoader";
import { IMCMediaDataReadRequest } from "./IMCMediaDataReadRequest";
import { IMCReadwriteReference } from "./IMCReadwriteReference";

/** 代表着一个媒体文件; 可以是一个 mp4 文件, 也可以是 hls 的 playlist 或 ts 等文件; */
export interface IMCMedia extends IMCReadwriteReference<IMCMedia> {
  readonly id: string;
  readonly contentType: Promise<string | undefined>; // mime type;
  readonly totalLength: Promise<number>;
  readonly byteRangeAccessSupported: Promise<boolean>;

  readonly isStored: Promise<boolean>;
  readonly completeness: Promise<number>; // 完成度; [0, 1];

  prepare(): Promise<void>;
  getContentLoadersBy(request: IMCMediaDataReadRequest): Promise<IMCMediaContentLoader[]>;

  on(event: 'metadataReady', callback: (media: IMCMedia) => void): void;
  off(event: 'metadataReady', callback: (media: IMCMedia) => void): void;
}