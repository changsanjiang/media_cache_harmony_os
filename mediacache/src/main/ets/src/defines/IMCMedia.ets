import { IMCMediaContent } from "./IMCMediaContent";
import { IMCMediaContentLoader } from "./IMCMediaContentLoader";
import { IMCMediaDataReadRequest } from "./IMCMediaDataReadRequest";
import { IMCReadwriteReference } from "./IMCReadwriteReference";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";

/** 代表着一个媒体文件; 可以是一个 mp4 文件, 也可以是 hls 的 playlist 文件或 ts 文件;
 *
 * 假设所有媒体都支持范围请求;
 * */
export interface IMCMedia extends IMCReadwriteReference<IMCMedia> {
  readonly id: string;
  readonly metadataReady: Promise<boolean>;
  readonly contentType: Promise<string | undefined>; // mime type;
  readonly totalLength: Promise<number>;

  readonly isStored: Promise<boolean>;
  readonly completeness: Promise<number>; // 完成度; [0, 1];

  prepare(rootDir: string): Promise<void>;
  createContentBy(responseHeaders: MCDownloadResponseHeaders): Promise<IMCMediaContent>; // throw if responseHeaders invalid; content readwrite is retained, should release after;
  getContentLoadersBy(request: IMCMediaDataReadRequest): Promise<IMCMediaContentLoader[]>;
}

//  Media 元数据的加载是通过 IMCMediaContentLoader 间接完成的, 所以当 dataLoaded 回调时, Reader 就可以直接读取这些元数据了;