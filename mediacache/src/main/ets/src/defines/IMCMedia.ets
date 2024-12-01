import { IMCMediaContent } from "./IMCMediaContent";
import { IMCMediaContentLoader } from "./IMCMediaContentLoader";
import { IMCReadwriteReference } from "./IMCReadwriteReference";
import { MCDownloadResponseHeaders } from "../utils/MCDownloadResponseHeaders";
import { IMCDataRequest } from "./IMCDataRequest";
import { MCRange } from "../utils/MCRange";
import { MCDownloadRequest } from "../utils/MCDownloadRequest";

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

  prepare(): Promise<void>;
  getContentLoadersBy(request: IMCDataRequest): Promise<IMCMediaContentLoader[]>; // 调用之前需要确保 media readwrite retained;

  // 解析内容范围
  // 如果是 206 请求, response 必须指定 content-range 字段;
  // 如果是 200 请求: 依赖于 content-length 字段, 有些服务器可能不返回这个字段;
  //
  // 200 或 206 => {start, length};
  // 当 200 请求的响应未指定 content-length 字段时返回 {0, Number.MAX_SAFE_INTEGER}
  parseContentRange(request: MCDownloadRequest, responseHeaders: MCDownloadResponseHeaders): Promise<MCRange>;
  // 当范围是 {0, Number.MAX_SAFE_INTEGER} 返回临时 content; 下载完成后通过 copyTempContent 保存到正式目录;
  createContentInRange(range: MCRange): Promise<IMCMediaContent>;
  // 当范围是 {0, Number.MAX_SAFE_INTEGER} 需要创建临时 content; 下载完成后通过 copyTempContent 保存到正式目录;
  createContentAt(offset: number, isTemp: boolean): Promise<IMCMediaContent>; // content readwrite is retained, should release after;
  destroyTempContent(content: IMCMediaContent): Promise<void>;
  copyTempContent(content: IMCMediaContent): Promise<void>;
}

//  Media 元数据的加载是通过 IMCMediaContentLoader 间接完成的, 所以当 dataLoaded 回调时, Reader 就可以直接读取这些元数据了;